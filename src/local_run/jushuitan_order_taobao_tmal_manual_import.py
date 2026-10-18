#!/usr/bin/env python3
"""
Script to load the latest Jushuitan Taobao/Tmall order export (Excel) from
INPUT_DIR, rename its Chinese column headers via COLUMN_RENAME_MAP, and
upload the result to BigQuery.

Usage:
    python local-run/jushuitan/jushuitan_order_taobao_tmal_manual_import.py
    python3 src/local_run/jushuitan_order_taobao_tmal_manual_import.py

"""

import warnings
import pytz
from datetime import datetime
import pandas as pd
from pathlib import Path
from google.cloud import bigquery
from google.oauth2 import service_account

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

EXCEL_EXTENSIONS = (".xlsx", ".xls")

# Resolved relative to the script's own location so it works on both Mac and
# Windows regardless of where "My Drive" is mounted (this file lives at
# ".../03. CODE & DOCUMENTS/lsoul_document/local-run/jushuitan/<script>.py",
# while raw_data/ is a sibling of lsoul_document, not inside it).
DATA_BASE_DIR = Path(__file__).resolve().parent.parent.parent
INPUT_DIR = DATA_BASE_DIR / "seeds" / "jushuitan_taobao_tmall_raw_data"

# BigQuery config — this script is expected to run from local-run/<folder>/,
# where credentials/google-credentials.json is a sibling of the script's parent.
BASE_DIR = Path(__file__).resolve().parent.parent.parent
SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


COLUMN_RENAME_MAP = {
    "内部订单号": "o_id",
    "线上订单号": "oo_id",
    "店铺编号": "shop_id",
    "店铺名称": "shop_name",
    "店铺主账号": "shop_account_no",
    "买家帐号": "buyer_account",
    "下单时间": "order_date",
    "付款日期": "payment_date",
    "运费": "freights",
    "店铺状态": "shop_status",
    "平台站点": "platform_site",
    "线上子订单编号": "so_id",
    "原始线上订单号": "raw_oo_id",
    "款号": "product_code",
    "商品编码": "items_sku_id",
    "数量": "items_qty",
    "商品单价": "items_price",
    "商品金额": "items_amount",
    "原价": "items_base_price",
    "子订单状态": "items_status",
    "分类": "items_category",
    "标准商品名": "items_group_name",
    "原始商品编码": "items_raw_sku_id",
    "退款状态": "items_refund_status",
    "卖家实收": "items_buyer_paid_amount",
    "登记数量": "items_registered_qty",
    "实退数量": "items_refund_qty",
    "订单退款金额": "items_refund_amount",
}



def get_latest_excel_file(input_dir):
    """Return the most recently modified Excel file in input_dir."""
    files = [
        f for f in input_dir.glob("*")
        if f.suffix.lower() in EXCEL_EXTENSIONS and not f.name.startswith("~$")
    ]
    if not files:
        raise FileNotFoundError(f"No Excel files found in {input_dir}")
    return max(files, key=lambda f: f.stat().st_mtime)


def load_data():
    """
    Find the latest Excel file in INPUT_DIR, load it, and rename/reorder
    its (Chinese) column headers according to COLUMN_RENAME_MAP.

    Returns:
        DataFrame with renamed columns, or empty DataFrame if the file has no rows.
    """
    latest_file = get_latest_excel_file(INPUT_DIR)
    print(f"\nLatest file found: {latest_file.name}")

    df = pd.read_excel(latest_file, dtype=str)
    print(f"Rows loaded: {len(df)}")

    if df.empty:
        return df

    df = rename_and_reorder_columns(df)
    df = trim_whitespace(df)
    return df


def trim_whitespace(df):
    """Strip leading/trailing whitespace from every string cell in the DataFrame."""
    for col in df.columns:
        if df[col].dtype == object:
            df[col] = df[col].str.strip()
    return df


def rename_and_reorder_columns(df):
    """
    Rename columns according to COLUMN_RENAME_MAP and filter to only include columns specified in the map.
    Columns are reordered to match the map's order. Any columns not in the map are excluded.
    
    Args:
        df: DataFrame loaded from the Excel export with Chinese column headers

    Returns:
        DataFrame with only renamed and reordered columns from COLUMN_RENAME_MAP
    """
    # First, rename columns that exist in the dataframe
    rename_dict = {k: v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns}
    df_renamed = df.rename(columns=rename_dict)
    
    # Get the desired column order from COLUMN_RENAME_MAP (the values)
    desired_order = list(COLUMN_RENAME_MAP.values())
    
    # Only include columns from COLUMN_RENAME_MAP (in order)
    final_column_order = [col for col in desired_order if col in df_renamed.columns]
    
    # Reorder the dataframe and only keep specified columns
    return df_renamed[final_column_order]


def convert_datetime_format(df):
    """
    Format datetime columns from 'YYYY-MM-DD HH:MM:SS' to 'YYYYMMDDHHMMSS' (no timezone conversion).
    Also adds 'vn_order_date' column: order_date converted from Shanghai to Vietnam timezone.

    Args:
        df: DataFrame with datetime columns in Shanghai timezone

    Returns:
        DataFrame with formatted datetime columns and new vn_order_date column
    """
    datetime_columns = ['order_date', 'payment_date']
    shanghai_tz = pytz.timezone('Asia/Shanghai')
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')

    for col in datetime_columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors='coerce')
            df[col] = df[col].dt.strftime('%Y%m%d%H%M%S')

    # Add vn_order_date: order_date converted from Shanghai to Vietnam timezone
    if 'order_date' in df.columns:
        vn_order_date = pd.to_datetime(df['order_date'], format='%Y%m%d%H%M%S', errors='coerce')
        vn_order_date = vn_order_date.dt.tz_localize(shanghai_tz).dt.tz_convert(vietnam_tz)
        df.insert(df.columns.get_loc('order_date') + 1, 'vn_order_date', vn_order_date.dt.strftime('%Y%m%d%H%M%S'))

    return df


def clean_nulls_for_bigquery(df):
    """Clean DataFrame by converting None, NaN, empty strings, and 'None' strings to proper NULL values."""
    df = df.replace({
        '': None,
        'None': None,
        'nan': None,
        'NaN': None,
        'null': None,
        'NULL': None,
    })
    df = df.where(pd.notna(df), None)
    return df


def insert_to_bigquery(df, project_id=None, dataset_id="jushuitan", table_id="raw_jushuitan_taobao_tmall_order_manual"):
    """Insert DataFrame into BigQuery."""
    df = clean_nulls_for_bigquery(df)

    # Convert all columns to string, preserving None values
    for col in df.columns:
        df[col] = df[col].apply(lambda x: str(x) if x is not None else None)

    client = bigquery.Client(project=project_id, credentials=credentials)
    try:
        table_ref = client.dataset(dataset_id).table(table_id)
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            autodetect=False,
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,
            ],
        )
        load_job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
        load_job.result()
        print(f"  ✓ Successfully loaded {load_job.output_rows} rows into {dataset_id}.{table_id}")
    finally:
        client.close()


def main():
    """
    Main function: load the latest Excel export from INPUT_DIR, rename its
    columns, and upload the result to BigQuery.
    """
    df_final = load_data()

    if not df_final.empty:
        # Convert datetime columns to YYYYMMDDHHMMSS format
        df_final = convert_datetime_format(df_final)

        print(f"\nInserting {len(df_final)} rows into BigQuery...")
        insert_to_bigquery(df_final)
        print(f"✓ Total records inserted: {len(df_final)}")
    else:
        print("\n✗ No data to insert.")


if __name__ == "__main__":
    main()