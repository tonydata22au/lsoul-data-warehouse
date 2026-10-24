#!/usr/bin/env python3
"""
Script to load inventory data from Surfosm API, flatten nested warehouse structures,
and export to BigQuery.

Usage:
    python3 local-run/surfosm/surfosm_data_export_inventory.py                                        # Default: yesterday
    python  local-run/surfosm/surfosm_data_export_inventory.py --date 2026-07-16                       # Single date
    python  local-run/surfosm/surfosm_data_export_inventory.py --start_date 2025-12-28 --end_date 2026-07-16
    python3 src/local_run/surfosm_inventory.py                     # Default: yesterday
    python3 src/local_run/surfosm_inventory.py --date 2026-07-16   # Single date
    python3 src/local_run/surfosm_inventory.py --start_date 2025-12-28 --end_date 2026-07-16
"""
import os
import argparse
import warnings
import requests
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
from google.cloud import bigquery
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)


# API Configuration
API_KEY = os.environ["SURFOSM_API_KEY"]
API_URL = "https://api-app.scaleup-fulfilment.com/openapi/inventory"

# BigQuery config — this script is expected to run from local-run/<folder>/,
# where credentials/google-credentials.json is a sibling of the script's parent.
BASE_DIR = Path(__file__).resolve().parent.parent.parent
SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


# Keys are the column names produced after json_normalize with record_path=['warehouses'].
# Meta fields (sku, barcode, product_name) are promoted to top-level columns.
# The 'stock' sub-object within each warehouse record is explicitly flattened in
# flatten_data(), yielding 'stock.on_hand', 'stock.normal', etc.
COLUMN_RENAME_MAP = {
    "as_of_date":                "as_of_date",
    "sku":                       "sku",
    "barcode":                   "barcode",
    "product_name":              "product_name",
    "warehouse_name":            "warehouse_name",
    "warehouse_code":            "warehouse_code",
    "stock.on_hand":             "stock_on_hand",
    "stock.normal":              "stock_normal",
    "stock.defect":              "stock_defect",
    "stock.quarantine":          "stock_quarantine",
    "stock.expired":             "stock_expired",
    "stock.shelf_life_hold":     "stock_shelf_life_hold",
    "stock.pending_destruction": "stock_pending_destruction",
    "updated_at":                "updated_at",
}


def fetch_inventory(date=None):
    """
    Fetch all inventory items for a given date, handling pagination.

    Args:
        date: Date string in 'YYYY-MM-DD' format, or None to omit the date param.

    Returns:
        List of inventory item dicts (each may contain a 'warehouses' list).
    """
    headers = {"x-api-key": API_KEY}
    all_items = []
    page_num = 1
    page_size = 1000

    while True:
        params = {"page": page_num, "per_page": page_size}
        if date:
            params["date"] = date

        try:
            response = requests.get(API_URL, params=params, headers=headers, timeout=9999)
            response.raise_for_status()
            payload = response.json()
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")

        data = payload.get("data", {})
        response_as_of_date = data.get("as_of_date", "")
        items = data.get("items", [])
        if not items:
            break

        # Ensure each item carries the API-level as_of_date for downstream flattening.
        for item in items:
            if isinstance(item, dict) and "as_of_date" not in item:
                item["as_of_date"] = response_as_of_date

        all_items.extend(items)
        total_pages = data.get("total_pages", 1)
        total = data.get("total", 0)
        print(f"  Fetched page {page_num}/{total_pages}: {len(items)} items "
              f"(total so far: {len(all_items)} of {total})")

        has_next_page = data.get("has_next_page", False)
        if not has_next_page or page_num >= total_pages:
            break

        page_num += 1

    label = date if date else "(no date filter)"
    print(f"  ✓ Fetched {len(all_items)} inventory items for {label}\n")
    return all_items
def flatten_data(raw_items):
    """
    Flatten inventory items by exploding the nested 'warehouses' array.
    Each resulting row represents one SKU × warehouse combination.

    Args:
        raw_items: List of inventory item dicts from the API.

    Returns:
        DataFrame with one row per SKU/warehouse, or empty DataFrame if no data.
    """
    if not raw_items:
        return pd.DataFrame()

    df = json_normalize(
        raw_items,
        record_path=["warehouses"],
        meta=["as_of_date", "sku", "barcode", "product_name"],
        errors="ignore",
    )

    # Explicitly flatten the 'stock' sub-object if json_normalize left it as a dict column.
    # This ensures stock.on_hand, stock.normal, etc. exist as individual columns.
    if "stock" in df.columns and df["stock"].apply(lambda x: isinstance(x, dict)).any():
        stock_df = pd.json_normalize(df["stock"].apply(lambda x: x if isinstance(x, dict) else {}).tolist())
        stock_df.columns = ["stock." + col for col in stock_df.columns]
        stock_df.index = df.index
        df = pd.concat([df.drop(columns=["stock"]), stock_df], axis=1)

    print(f"  Data structure:")
    print(f"    Items from API   : {len(raw_items)}")
    print(f"    Rows (SKU×WH)    : {len(df)}")
    print(f"    Columns          : {len(df.columns)}")

    return df.copy()


def rename_and_reorder_columns(df):
    """
    Select and rename columns according to COLUMN_RENAME_MAP.
    Missing columns are filled with empty strings.
    """
    new_df_dict = {}

    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
        else:
            new_df_dict[new_col] = pd.Series([""] * len(df), index=df.index)

    result_df = pd.DataFrame(new_df_dict)

    # Normalise updated_at to %Y-%m-%dT%H:%M:%S (strip milliseconds / timezone suffix)
    if "updated_at" in result_df.columns:
        def _fmt_updated_at(val):
            if not val or val == '' or pd.isna(val):
                return ''
            try:
                clean = str(val).replace('Z', '').split('+')[0].split('.')[0]
                return datetime.strptime(clean, '%Y-%m-%dT%H:%M:%S').strftime('%Y%m%d%H%M%S')
            except (ValueError, AttributeError):
                return val
        result_df["updated_at"] = result_df["updated_at"].apply(_fmt_updated_at)

    return result_df


def insert_to_bigquery(df, project_id=None, dataset_id="surfosm", table_id="raw_surfosm_inventory"):
    """Insert DataFrame into BigQuery."""

    # Convert all columns to string, preserving None as None
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
    parser = argparse.ArgumentParser(description="Export Surfosm inventory data to BigQuery")
    parser.add_argument("--date", default=None, help="Single date in format YYYY-MM-DD")
    parser.add_argument("--start_date", default=None, help="Start date in format YYYY-MM-DD")
    parser.add_argument("--end_date", default=None, help="End date in format YYYY-MM-DD")
    args = parser.parse_args()

    dates_to_fetch = []

    if args.start_date and args.end_date:
        try:
            start = datetime.strptime(args.start_date, "%Y-%m-%d")
            end = datetime.strptime(args.end_date, "%Y-%m-%d")
        except ValueError as e:
            print(f"Error parsing dates: {e}")
            return

        if start > end:
            print("Error: start_date must be before or equal to end_date")
            return

        current = start
        while current <= end:
            dates_to_fetch.append(current.strftime("%Y-%m-%d"))
            current += timedelta(days=1)

    elif args.date:
        dates_to_fetch = [args.date]

    else:
        # Default: yesterday
        yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        dates_to_fetch = [yesterday]

    all_frames = []

    for date in dates_to_fetch:
        print(f"Fetching inventory for date: {date}")
        raw_items = fetch_inventory(date=date)

        if not raw_items:
            print(f"  No inventory items found for {date}, skipping.")
            continue

        df = flatten_data(raw_items)
        if df.empty:
            print(f"  No rows after flattening for {date}, skipping.")
            continue

        # No updated_at filter: rely on API date parameter.
        df = rename_and_reorder_columns(df)
        final_columns = list(COLUMN_RENAME_MAP.values())
        df = df.reindex(columns=final_columns, fill_value="")
        all_frames.append(df)

    if not all_frames:
        print("✗ No data to insert.")
        return

    combined_df = pd.concat(all_frames, ignore_index=True)
    print(f"\nInserting {len(combined_df)} rows to BigQuery...")
    insert_to_bigquery(combined_df)
    print(f"✓ Total rows processed: {len(combined_df)}")


if __name__ == "__main__":
    main()
