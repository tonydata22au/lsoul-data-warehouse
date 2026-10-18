#!/usr/bin/env python3
"""
Script to load the latest Jushuitan Taobao/Tmall order export (Excel) from
INPUT_DIR, rename its Chinese column headers via COLUMN_RENAME_MAP, and
export the result as a CSV file.

Usage:
    python versions/CSV_V1_manual_jushuitan_taobao_tmall_order_manual.py

"""

import warnings
import pytz
from datetime import datetime
import pandas as pd
from pathlib import Path

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

EXCEL_EXTENSIONS = (".xlsx", ".xls")

# Resolved relative to the script's own location so it works on both Mac and
# Windows regardless of where "My Drive" is mounted (this file lives at
# ".../03. CODE & DOCUMENTS/lsoul_document/versions/<script>.py").
BASE_DIR = Path(__file__).resolve().parent.parent.parent
INPUT_DIR = BASE_DIR / "raw_data" / "jushuitan_taobao_tmall_raw_data"
OUTPUT_DIR = BASE_DIR / "data_export_csv"


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


def main():
    """
    Main function: load the latest Excel export from INPUT_DIR, rename its
    columns, and save the result as a CSV file in OUTPUT_DIR.
    """
    df_final = load_data()

    # Save to CSV
    if not df_final.empty:
        # Convert datetime columns to YYYYMMDDHHMMSS format
        df_final = convert_datetime_format(df_final)
        
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = OUTPUT_DIR / f"jushuitan-taobao-tmall-order_{timestamp}.csv"
        
        df_final.to_csv(output_file, index=False, encoding='utf-8-sig')
        print(f"\n✓ Data saved to: {output_file}")
        print(f"✓ Total records: {len(df_final)}")
    else:
        print("\n✗ No data to save.")


if __name__ == "__main__":
    main()