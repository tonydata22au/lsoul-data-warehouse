import argparse
import logging
import os
import warnings
from datetime import datetime, timedelta, timezone

import pandas as pd
import pytz
import requests
import urllib3
from flask import Flask
from google.cloud import bigquery
from google.oauth2 import service_account
from pandas import json_normalize
from pathlib import Path# Disable SSL warnings for development/testing
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logging.basicConfig(level=logging.INFO)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

COLUMN_RENAME_MAP = {
    # Product-level columns
    "inserted_at": "inserted_at",
    "updated_at": "updated_at",
    "id": "product_id",
    "name": "product_name",
    "custom_id": "custom_id",
    "display_id": "display_id",
    "image": "image",
    "wholesale_price": "wholesale_price",
    "product_attributes": "product_attributes",
    "supplier_product_ids": "supplier_product_ids",
    "tags": "tags",
    "type": "type",
    # Variation-level columns
    "variations.average_imported_price": "variation_average_imported_price",
    "variations.display_id": "variation_display_id",
    "variations.inserted_at": "variation_inserted_at",
    "variations.is_hidden": "variation_is_hidden",
    "variations.is_locked": "variation_is_locked",
    "variations.is_removed": "variation_is_removed",
    "variations.is_sell_negative_variation": "variation_is_sell_negative",
    "variations.last_imported_price": "variation_last_imported_price",
    "variations.price_at_counter": "variation_price_at_counter",
    "variations.remain_quantity": "variation_remain_quantity",
    "variations.retail_price": "variation_retail_price",
    "variations.retail_price_after_discount": "variation_retail_price_after_discount",
    "variations.total_purchase_price": "variation_total_purchase_price",
    # Warehouse-level columns
    "variations.variation_warehouses.actual_remain_quantity": "variation_warehouse_actual_remain_quantity",
    "variations.variation_warehouses.total_quantity": "variation_warehouse_total_quantity",
    "variations.variation_warehouses.warehouse_id": "variation_warehouse_id",
    "variations.variation_warehouses.returning_quantity": "variation_warehouse_returning_quantity",    
    "variations.variation_warehouses.waiting_quantity": "variation_warehouse_waiting_quantity",
    
                #"categories": [],      
                 #"is_sell_negative": "is_sell_negative",          
                 #"is_published": null,
                 #"is_published": null,
                 #"manipulation_warehouses": [],
                #"measure_group_id": null,
                #"note": null,
                #"note_product": "",
                    #"variations.is_composite": "variation_is_composite",
                    #"barcode": "Z26010017-4",
                    #"bonus_variations": [],
                    #"composite_products": [],
                    # "batch_position": null,
                    # "pending_quantity": 0,  
                    #"variations.variation_warehouses.selling_avg": "variation_warehouse_selling_avg",
}

WAREHOUSE_FIELDS = ['actual_remain_quantity', 'total_quantity', 'warehouse_id', 
                    'returning_quantity', 'waiting_quantity']


def parse_date_to_unix(date_string):
    """
    Convert date string in format 'YYYY-MM-DDTHH:MM:SS' (Vietnam time) to Unix timestamp.
    
    Args:
        date_string: Date string in format '2024-01-01T00:00:00' in Vietnam time or None
        
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

def load_data(start_date=None, end_date=None, max_pages=None):
    """
    Load product data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/products"
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
    
    while True:
        params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
            }
        if start_datetime:
            params['start_time_update'] = start_datetime
        if end_datetime:
            params['end_time_update'] = end_datetime
        
        try:
            response = requests.get(api_url, params=params, timeout=9999)
            response.raise_for_status()
            payload = response.json()
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        
        products = payload.get("data", [])
        if not products:
            break
        
        all_products.extend(products)
        total_pages = payload.get("total_pages", 1)
        print(f"  Fetched page {page}/{total_pages}: {len(products)} entries (total: {len(all_products)})")
        
        if len(products) < page_size and page >= total_pages:
            break

        page += 1
    
    print(f"Successfully fetched {len(all_products)} products from API\n")
    return all_products


def flatten_data(products_raw):
    """Flatten nested product data and explode warehouse arrays into separate rows."""
    has_variations = any(isinstance(p.get("variations"), list) and p["variations"] for p in products_raw)
    
    if not has_variations:
        df = json_normalize(products_raw, sep=".", errors="ignore")
        print(f"\nData Structure: {len(products_raw)} products → {len(df)} rows")
        return df
    
    # Flatten variations into rows
    meta_cols = [col for col in products_raw[0].keys() if col != "variations"]
    df = json_normalize(products_raw, record_path="variations", meta=meta_cols,
                        record_prefix="variations.", sep=".", errors="ignore")
    
    print(f"\nData Structure:")
    print(f"  Products: {len(products_raw)} → Variations: {len(df)}")
    
    # Find warehouse column (handles both naming conventions)
    warehouse_col = next((c for c in df.columns if 'warehouses' in c.lower() and 'variations' in c.lower()), None)
    if not warehouse_col:
        return df
    
    # Explode warehouses: vectorized approach
    df[warehouse_col] = df[warehouse_col].apply(lambda x: x if isinstance(x, list) and x else [{}])
    df = df.explode(warehouse_col, ignore_index=True)
    
    # Extract warehouse fields using vectorized operations
    warehouse_data = df[warehouse_col].apply(lambda x: x if isinstance(x, dict) else {})
    for field in WAREHOUSE_FIELDS:
        df[f'variations.variation_warehouses.{field}'] = warehouse_data.apply(lambda x: x.get(field))
    
    print(f"  After warehouse explode: {len(df)} rows")
    return df


def rename_and_reorder_columns(df):
    # Include all columns from COLUMN_RENAME_MAP, creating empty columns for missing data
    # This ensures consistent column structure across all exports
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
    date_columns = ['inserted_at','updated_at', 'variation_inserted_at'
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


def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    # Only process object/string columns to preserve numeric types
    for col in df.columns:
        if df[col].dtype == 'object':
            df[col] = df[col].astype(str).replace(['nan', '{}','[]','None'], '')
    return df

def normalize_id_strings(df):
    """Normalize ID-like columns to remove float-ish suffixes (e.g., 123456.0 → 123456)."""
    id_like_cols = [
        "variation_is_hidden",
        "variation_is_locked",
        "variation_is_removed",
        "variation_is_sell_negative",
        "variation_remain_quantity",
        "variation_warehouse_actual_remain_quantity",
        "variation_warehouse_returning_quantity",
        "variation_warehouse_total_quantity",
        "variation_warehouse_waiting_quantity"
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

def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_product"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique products and total rows]
    unique_products = df['product_id'].nunique() if 'product_id' in df.columns else len(df)
    total_rows = len(df)
    
    # Initialize BigQuery client with service account credentials
    client = bigquery.Client(project=project_id) if project_id else bigquery.Client()
    
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
        
        # Load data from DataFrame to BigQuery
        load_job = client.load_table_from_dataframe(
            df, table_ref, job_config=job_config
        )
        load_job.result()  # Wait for completion
        
        print(f"✓ Successfully loaded {load_job.output_rows} rows to {dataset_id}.{table_id} [{load_job.job_id}]")
        print(f"  Unique products: {unique_products}")
        print(f"  Total rows (product items): {total_rows}")
        
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")

def run_export(*, project_id=None, all_flag=False, start_date=None, end_date=None, max_pages=None, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
    # Determine date range based on options:
    # 1. Manual dates: Use provided start_date and end_date
    # 2. all_flag: No date filters
    # 3. Default: Yesterday 00:00:00 to 23:59:59
    if start_date or end_date:
        start_date_arg = start_date
        end_date_arg = end_date
    elif all_flag:
        start_date_arg = None
        end_date_arg = None
    else:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")


    products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg, max_pages=max_pages)
    
    # Check if there are any products
    if not products_raw or len(products_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(products_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)
    df = normalize_id_strings(df)

    if dry_run:
        print(f"DRY RUN: {len(df)} rows ready for load (unique transfers: {df['product_id'].nunique() if 'product_id' in df.columns else len(df)})")
        print(df.head())
        return "Dry run complete", 200

    message = insert_to_bigquery(df, project_id=project_id)
    return message or "Success", 200

def main(argv=None):
    parser = argparse.ArgumentParser(description="Export Pancake POS entry data to BigQuery")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", default=False, help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    parser.add_argument("--max-pages", type=int, default=None, help="Limit number of pages to fetch (for testing)")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and transform only; skip BigQuery load")
    args = parser.parse_args(argv)

    run_export(
        project_id=args.project_id,
        all_flag=args.All,
        start_date=args.start_date,
        end_date=args.end_date,
        max_pages=args.max_pages,
        dry_run=args.dry_run,
    )

app = Flask(__name__)

@app.route("/")
def run():
    logging.info("Triggering Pancake order data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500

    
if __name__ == "__main__":
    main()

# Placeholder for next edit
