#!/usr/bin/env python3
"""
Script to load inventory history data from Pancake API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's inventory_histories from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)

Usage:
    python3 local-run/pancake/data_export_inventory_histories.py               # Get yesterday's inventory_histories from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)
    python3 local-run/pancake/data_export_inventory_histories.py --start_date 2025-12-25T00:00:00 --end_date 2026-06-1T23:59:59
    python3 local-run/pancake/data_export_inventory_histories.py --All           # Get all inventory_histories with no date filter (use with caution)
"""
import argparse
import os
import time
import warnings
import requests
from datetime import datetime, timedelta, timezone
import pandas as pd
from pandas import json_normalize
import pytz
import urllib3
from pathlib import Path
from google.cloud import bigquery
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


COLUMN_RENAME_MAP = {

   #Variation-level fields (from API response):
            
            "id": "inventory_history_id",
            "inserted_at": "inserted_at",
            "record_id": "record_id",
            "ref_display_id": "ref_display_id",
            "table_name": "table_name",
            "note_type": "note_type",
            "type": "type",
            "warehouse.id": "warehouse_id",
            "warehouse.name": "warehouse_name",
            
            "avg_price": "avg_price",
            "quantity": "quantity",
            "remain_quantity": "remain_quantity",
            "is_actual_remain_quantity": "is_actual_remain_quantity",
            "supplier_products_id": "supplier_products_id",
            "user.id": "user_id",
            "user.name": "user_name",
   
            "variation_now.inserted_at": "variation_inserted_at",
            "variation_now.updated_at": "variation_updated_at",
            "variation_now.product_id": "variation_product_id",
            "variation_now.id": "variation_id",
            "variation_now.display_id": "variation_display_id",
            "variation.name": "variation_name",
            "variation.remain_quantity": "variation_remain_quantity",
            "variation.total_quantity": "variation_total_quantity",

              
                "variation_now.is_composite": "variation_is_composite",
                "variation_now.is_hidden": "variation_is_hidden",
                "variation_now.is_locked": "variation_is_locked",
                "variation_now.is_removed": "variation_is_removed",
                "variation_now.is_sell_negative_variation": "variation_is_sell_negative_variation",
                "variation_now.last_imported_price": "variation_last_imported_price",
                "variation_now.price_at_counter": "variation_price_at_counter",
                "variation_now.retail_price": "variation_retail_price",
                "variation_now.retail_price_after_discount": "variation_retail_price_after_discount",
                "variation_now.wholesale_price": "variation_wholesale_price",

                    "current_inventory.id": "current_inventory_warehouse_id",
                    "current_inventory.name": "current_inventory_name",
                    "current_inventory.actual_remain_quantity":  "current_inventory_actual_remain_quantity",
                    "current_inventory.remain_quantity": "current_inventory_remain_quantity",
                    "current_inventory.total_quantity": "current_inventory_total_quantity",
                
}

def parse_date_to_unix(date_string):
    """
    Convert date string in format 'YYYY-MM-DDTHH:MM:SS' to Unix timestamp.
    
    Args:
        date_string: Date string in format '2024-01-01T00:00:00' or None
        
    Returns:
        Unix timestamp (int) or None if date_string is empty/None
    """
    if not date_string or date_string.strip() == "":
        return None
    
    try:
        # Parse as Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        dt_vietnam = vietnam_tz.localize(dt)
        return int(dt_vietnam.timestamp())
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")

def load_data(start_date=None, end_date=None):
    """
    Load inventory history data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/inventory_histories"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_products = []
    page = 1
    page_size = 1000
    
    # Convert date strings to Unix timestamps
    # Note: Input dates are treated as Vietnam time (UTC+7) and converted to Unix timestamp for API
    start_datetime = parse_date_to_unix(start_date)
    end_datetime = parse_date_to_unix(end_date)
    
    print("Fetching data from API...")
    if start_datetime or end_datetime:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        if start_datetime:
            # Show both Vietnam time (input) and UTC time (what API receives)
            vietnam_start = datetime.fromtimestamp(start_datetime, tz=vietnam_tz)
            utc_start = datetime.fromtimestamp(start_datetime, tz=pytz.UTC)
            print(f"  Start date (Vietnam/Input): {start_date} → UTC: {utc_start.strftime('%Y-%m-%d %H:%M:%S')} (Unix: {start_datetime})")
        if end_datetime:
            # Show both Vietnam time (input) and UTC time (what API receives)
            vietnam_end = datetime.fromtimestamp(end_datetime, tz=vietnam_tz)
            utc_end = datetime.fromtimestamp(end_datetime, tz=pytz.UTC)
            print(f"  End date (Vietnam/Input): {end_date} → UTC: {utc_end.strftime('%Y-%m-%d %H:%M:%S')} (Unix: {end_datetime})")
    else:
        print(f"  No date filters applied - fetching all data")
    
    max_retries = 5
    retry_delay = 10  # seconds between retries

    while True:
        params = {
            'api_key': api_key,
            'page': page,
            'page_size': page_size,
        }
        if start_datetime:
            params['startDate'] = start_datetime
        if end_datetime:
            params['endDate'] = end_datetime

        for attempt in range(1, max_retries + 1):
            try:
                response = requests.get(api_url, params=params, timeout=99999)
                response.raise_for_status()
                break  # success — exit retry loop
            except requests.exceptions.HTTPError as e:
                if response.status_code == 500 and attempt < max_retries:
                    print(f"  Warning: 500 error on page {page} (attempt {attempt}/{max_retries}), retrying in {retry_delay}s...")
                    time.sleep(retry_delay)
                else:
                    raise ValueError(f"API request failed: {e}")
            except requests.exceptions.RequestException as e:
                raise ValueError(f"API request failed: {e}")

        try:
            payload = response.json()
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")

        products = payload.get("data", [])
        if not products:
            break

        all_products.extend(products)
        total_pages = payload.get("total_pages", 1)
        print(f"  Fetched page {page}/{total_pages}: {len(products)} entries (total: {len(all_products)})")

        if len(products) < page_size and page >= total_pages:
            break

        page += 1
    
    print(f"Successfully fetched {len(all_products)} variations from API\n")
    return all_products


def flatten_data(products_raw):
    has_items = any(isinstance(o.get("variation_now"), list) and o.get("variation_now") for o in products_raw)
    
    if has_items:
        # Pre-explode variation_now list so that json_normalize(sep=".") can flatten all
        # nested dicts (user, warehouse, variation, variation_now) into dotted column names
        # that match COLUMN_RENAME_MAP keys (e.g. "variation_now.inserted_at", "user.id").
        # Using record_prefix="variation_now_" with json_normalize would produce underscore-
        # separated names that never match the map, and meta fields would stay as dict columns.
        exploded_records = []
        for record in products_raw:
            vn_list = record.get("variation_now", [])
            if isinstance(vn_list, list) and vn_list:
                base = {k: v for k, v in record.items() if k != "variation_now"}
                for vn in vn_list:
                    exploded_records.append({**base, "variation_now": vn if isinstance(vn, dict) else {}})
            else:
                exploded_records.append(record)
        df = json_normalize(exploded_records, sep=".", errors="ignore")
        print(f"\nData Structure:")
        print(f"  1st level records from API: {len(products_raw)}")
        print(f"  Inventory histories (rows): {len(df)}")
        print(f"  Note: Each product variation creates a separate row in the table")
        print(f"  2nd level columns: {len([c for c in df.columns if c.startswith('variation_now.')])}")
        print(f"  1st level columns: {len([c for c in df.columns if not c.startswith('variation_now.')])}")
    else:
        df = json_normalize(products_raw, sep=".", errors="ignore")
        print(f"\nData Structure:")
        print(f"  1st level records from API: {len(products_raw)}")
        print(f"  Rows to insert: {len(df)}")

    # Backfill user fields without overwriting already-flattened values.
    # API payloads can vary between nested user object and flat user_id/user_name fields.
    def _is_missing(val):
        return pd.isna(val) or str(val).strip() in ('', 'nan', 'None', 'null')

    if 'user.id' not in df.columns:
        df['user.id'] = None
    if 'user.name' not in df.columns:
        df['user.name'] = None

    if 'user' in df.columns:
        user_id_from_obj = df['user'].apply(lambda x: x.get('id') if isinstance(x, dict) else None)
        user_name_from_obj = df['user'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)
        df['user.id'] = [base if not _is_missing(base) else extra for base, extra in zip(df['user.id'], user_id_from_obj)]
        df['user.name'] = [base if not _is_missing(base) else extra for base, extra in zip(df['user.name'], user_name_from_obj)]

    if 'user_id' in df.columns:
        df['user.id'] = [base if not _is_missing(base) else extra for base, extra in zip(df['user.id'], df['user_id'])]
    if 'user_name' in df.columns:
        df['user.name'] = [base if not _is_missing(base) else extra for base, extra in zip(df['user.name'], df['user_name'])]

    return df.copy()


def expand_current_inventory(df):
    """Explode current_inventory list into one row per warehouse."""
    if 'current_inventory' not in df.columns:
        return df

    df = df.explode('current_inventory').reset_index(drop=True)

    wh_expanded = pd.json_normalize(
        df['current_inventory'].apply(lambda x: x if isinstance(x, dict) else {})
    ).add_prefix('current_inventory.')

    df = df.drop(columns=['current_inventory']).reset_index(drop=True)
    df = pd.concat([df, wh_expanded], axis=1)
    return df


def rename_and_reorder_columns(df):
    # Keep all columns from the dataframe (don't filter by COLUMN_RENAME_MAP)
    # Just rename the ones that exist in the mapping
    new_df_dict = {}

    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]

    return pd.DataFrame(new_df_dict)

def convert_booleans_to_binary(df):
    # Only process columns that actually contain True/False values
    for col in df.columns:
        str_vals = df[col].astype(str)
        true_count = (str_vals == 'True').sum()
        false_count = (str_vals == 'False').sum()
        
        # If column has True/False values, convert them
        if (true_count + false_count) > 0:
            # Use map with fillna to avoid FutureWarning about downcasting
            mapping = {True: 1, 'True': 1, False: 0, 'False': 0}
            df[col] = df[col].map(lambda x: mapping.get(x, x))
    return df


def convert_dates_to_timestamp(df):
    date_columns = [
        'inserted_at','variation_inserted_at','variation_updated_at'
    ]
    
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    
    for col in date_columns:
        if col in df.columns:
            try:
                # Convert to datetime with UTC timezone first (API returns UTC), then convert to Vietnam time
                df[col] = pd.to_datetime(df[col], utc=True).dt.tz_convert(vietnam_tz).dt.strftime('%Y%m%d%H%M%S')
            except:
                pass
    return df


def normalize_id_strings(df):
    """Normalize ID-like columns to remove float-ish suffixes (e.g., 123456.0 → 123456)."""
    id_like_cols = [  
        "is_actual_remain_quantity",
        "quantity",
        "remain_quantity",
        "variation_is_hidden",
        "variation_is_locked",
        "variation_is_removed",
        "variation_is_composite",
        "variation_remain_quantity",
        "variation_total_quantity",
        "current_inventory_actual_remain_quantity",
        "current_inventory_pending_quantity",
        "current_inventory_remain_quantity",
        "current_inventory_returning_quantity",
        "current_inventory_total_quantity",
        "current_inventory_waiting_quantity"
    ]
    def strip_floatish(val):
        try:
            f = float(val)
        except (TypeError, ValueError):
            return str(val)
        # Preserve NaN/inf as-is (string form) to avoid accidental coercion
        if pd.isna(f) or f in (float("inf"), float("-inf")):
            return str(val)
        if f.is_integer():
            return str(int(f))
        return str(val)

    for col in id_like_cols:
        if col in df.columns:
            df[col] = df[col].apply(strip_floatish)
    return df

def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    # Only process object/string columns to preserve numeric types
    for col in df.columns:
        if df[col].dtype == 'object':
            df[col] = df[col].astype(str).replace(['nan', '{}','[]','None','null'], '')
    return df

def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_inventory_histories"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique products and total rows
    unique_products = df['variation_id'].nunique() if 'variation_id' in df.columns else len(df)
    total_rows = len(df)
    
    # Initialize BigQuery client with service account credentials
    client = bigquery.Client(project=project_id, credentials=credentials)
    
    try:
        # Construct table reference
        table_ref = client.dataset(dataset_id).table(table_id)
        
        # Get existing table schema to match types
        try:
            existing_table = client.get_table(table_ref)
            
        except Exception as e:
            print(f"  Warning: Could not get existing table schema: {e}")
            print(f"  Proceeding with autodetect...")
        
        # Configure load job - let BigQuery autodetect schema
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",  # Appends without overwriting
            autodetect=False,  # Don't autodetect - use existing table schema
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,  # Allow relaxing required to nullable
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,  # Allow adding new fields
            ],
        )
        
        # Convert all columns to string to match BigQuery STRING schema
        for col in df.columns:
            df[col] = df[col].astype(str).replace('nan', '').replace('None', '')

        # Upload in chunks to avoid PyArrow memory errors on large DataFrames
        chunk_size = 5000
        total_loaded = 0
        chunks = [df.iloc[i:i + chunk_size] for i in range(0, len(df), chunk_size)]
        for idx, chunk in enumerate(chunks, start=1):
            load_job = client.load_table_from_dataframe(
                chunk, table_ref, job_config=job_config
            )
            load_job.result()
            total_loaded += load_job.output_rows
            print(f"  Chunk {idx}/{len(chunks)}: loaded {load_job.output_rows} rows [{load_job.job_id}]")

        print(f"✓ Successfully loaded {total_loaded} rows to {dataset_id}.{table_id}")
        print(f"  Unique variations: {unique_products}")
        print(f"  Total rows (variation items): {total_rows}")
        
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")

def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS entry data to BigQuery")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", default=False, help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    parser.add_argument("--yesterday", action="store_true", help="Fetch data from yesterday only (default behavior)")
    args = parser.parse_args()
    
    # Determine date range based on options:
    # 1. Manual dates: Use provided --start-date and --end-date
    # 2. --All flag: No date filters
    # 3. Default: Yesterday 00:00:00 to 23:59:59
    if args.start_date or args.end_date:
        start_date_arg = args.start_date
        end_date_arg = args.end_date
    elif args.All:
        # Fetch all data (no date filters)
        start_date_arg = None
        end_date_arg = None
    else:
        # Default: Yesterday in Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")

    products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any products
    if not products_raw or len(products_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(products_raw)
    df = expand_current_inventory(df)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = normalize_id_strings(df)
    df = clean_empty_json(df)

    insert_to_bigquery(df, project_id=args.project_id)
    
if __name__ == "__main__":
    main()

# Placeholder for next edit
