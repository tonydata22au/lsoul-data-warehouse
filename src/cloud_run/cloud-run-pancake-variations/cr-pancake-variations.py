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
    # Maps from flatten_data() output columns to desired final names
    # Base variation fields
    "inserted_at": "inserted_at",
    "updated_at": "updated_at",
    "id": "variation_id",
    "display_id": "display_id",
    "fields": "fields", 
    "is_hidden": "is_hidden",
    "is_locked": "is_locked",
    "is_sell_negative_variation": "is_sell_negative_variation",
    "last_imported_price": "last_imported_price",
    "price_at_counter": "price_at_counter",
    "product_id": "product_id",
    "remain_quantity": "remain_quantity",
    "retail_price": "retail_price",
    # Product nested fields (from product object)
    "variation.product.display_id": "variation_product_display_id",
    "variation.product.inserted_at": "variation_product_inserted_at",
    "variation.product.name": "variation_product_name",
    "variation.product.product_attributes": "variation_product_attributes",
    "variation.product.supplier_product_ids": "variation_product_supplier_product_ids",
    "variation.product.tags": "variation_product_tags",
    # Warehouse nested fields (from variations_warehouses array)
    "variation.variations_warehouses.actual_remain_quantity": "variations_warehouses_actual_remain_quantity",
    "variation.variations_warehouses.pending_quantity": "variations_warehouses_pending_quantity",
    "variation.variations_warehouses.remain_quantity": "variations_warehouses_remain_quantity",
    "variation.variations_warehouses.returning_quantity": "variations_warehouses_returning_quantity",
    "variation.variations_warehouses.total_quantity": "variations_warehouses_total_quantity",
    "variation.variations_warehouses.waiting_quantity": "variations_warehouses_waiting_quantity",
    "variation.variations_warehouses.warehouse_id": "variations_warehouses_warehouse_id"           
}


def load_data(start_date=None, end_date=None, max_pages=None):
    """
    Load product data from Pancake API (fetches all data without date filtering).
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/variations"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_products = []
    page = 1
    page_size = 1000
    
    print(f"Fetching data from API...")

    while True:
        if max_pages and page > max_pages:
            print(f"  Reached max_pages={max_pages}, stopping fetch")
            break
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size
            }

            response = requests.get(api_url, params=params, timeout=169)
            response.raise_for_status()
            payload = response.json()
            
            products = payload.get("data", [])
            if not products:
                break
            
            all_products.extend(products)
            total_pages = payload.get("total_pages", 1)
            print(f"  Fetched page {page}/{total_pages}: {len(products)} entries (total: {len(all_products)})")
            
            # Check if there are more pages
            if len(products) < page_size and page >= total_pages:
                break
            
            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"Successfully fetched {len(all_products)} products from API\n")
    return all_products

def filter_data_by_date(entries, start_date=None, end_date=None):
    """
    Filter entries based on inserted_at column.
    
    Args:
        entries: List of entries from API
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
        
    Returns:
        Filtered list of entries
    """
    if not start_date and not end_date:
        print("No date filters applied - using all data")
        return entries
    
    # Parse filter dates as naive datetime
    start_datetime = datetime.strptime(start_date, "%Y-%m-%dT%H:%M:%S") if start_date else None
    end_datetime = datetime.strptime(end_date, "%Y-%m-%dT%H:%M:%S") if end_date else None
    
    print(f"Filtering data by updated_at...")
    utc_start = None
    utc_end = None
    if start_datetime or end_datetime:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        if start_datetime:
            # Localize to Vietnam time then convert to UTC
            vietnam_start = vietnam_tz.localize(start_datetime)
            utc_start = vietnam_start.astimezone(pytz.UTC)
            print(f"  Start date (Vietnam/Input): {start_date} → UTC: {utc_start.strftime('%Y-%m-%d %H:%M:%S')}")
        if end_datetime:
            # Localize to Vietnam time then convert to UTC
            vietnam_end = vietnam_tz.localize(end_datetime)
            utc_end = vietnam_end.astimezone(pytz.UTC)
            print(f"  End date (Vietnam/Input): {end_date} → UTC: {utc_end.strftime('%Y-%m-%d %H:%M:%S')}")
    
    filtered_entries = []
    for entry in entries:
        updated_at = entry.get("updated_at")
        if not updated_at:
            continue
        
        try:
            # Handle both formats: with and without microseconds
            if "." in updated_at:
                entry_dt = datetime.strptime(updated_at.split(".")[0], "%Y-%m-%dT%H:%M:%S")
            else:
                entry_dt = datetime.strptime(updated_at, "%Y-%m-%dT%H:%M:%S")
            
            # Make entry_dt timezone-aware (UTC) for comparison
            entry_dt = pytz.UTC.localize(entry_dt)
            
            # Apply date filters
            if utc_start and entry_dt < utc_start:
                continue
            if utc_end and entry_dt > utc_end:
                continue
            
            filtered_entries.append(entry)
        except ValueError:
            # If date parsing fails, skip the entry
            continue
    
    print(f"  Filtered: {len(entries)} → {len(filtered_entries)} entries\n")
    return filtered_entries


def flatten_data(entries_raw):
    """Flatten variation data, expanding warehouses into separate rows with all nested fields extracted."""
    
    rows = []
    
    for entry in entries_raw:
        # Get all base variation-level fields (exclude nested objects)
        base_fields = {k: v for k, v in entry.items() if k not in ['product', 'variations_warehouses']}
        
        # Get product object (single object, not a list)
        product = entry.get('product', {})
        
        # Get variations_warehouses array
        var_warehouses_list = entry.get('variations_warehouses', [])
        
        # If there are warehouses, create one row per warehouse
        if isinstance(var_warehouses_list, list) and len(var_warehouses_list) > 0:
            for warehouse in var_warehouses_list:
                row = base_fields.copy()
                
                # Add product-level fields (product is an object, not a list)
                if isinstance(product, dict):
                    row['variation.product.categories'] = product.get('categories', [])
                    row['variation.product.display_id'] = product.get('display_id', '')
                    row['variation.product.inserted_at'] = product.get('inserted_at', '')
                    row['variation.product.name'] = product.get('name', '')
                    row['variation.product.product_attributes'] = product.get('product_attributes', [])
                    row['variation.product.supplier_product_ids'] = product.get('supplier_product_ids', [])
                
                # Add warehouse-level fields
                row['variation.variations_warehouses.actual_remain_quantity'] = warehouse.get('actual_remain_quantity', 0)
                row['variation.variations_warehouses.pending_quantity'] = warehouse.get('pending_quantity', 0)
                row['variation.variations_warehouses.remain_quantity'] = warehouse.get('remain_quantity', 0)
                row['variation.variations_warehouses.returning_quantity'] = warehouse.get('returning_quantity', 0)
                row['variation.variations_warehouses.selling_avg'] = warehouse.get('selling_avg', 0)
                row['variation.variations_warehouses.total_quantity'] = warehouse.get('total_quantity', 0)
                row['variation.variations_warehouses.waiting_quantity'] = warehouse.get('waiting_quantity', 0)
                row['variation.variations_warehouses.warehouse_id'] = warehouse.get('warehouse_id', '')
                
                rows.append(row)
        else:
            # No warehouses, create a single row with product info
            row = base_fields.copy()
            
            # Add product-level fields
            if isinstance(product, dict):
                row['variation.product.categories'] = product.get('categories', [])
                row['variation.product.display_id'] = product.get('display_id', '')
                row['variation.product.inserted_at'] = product.get('inserted_at', '')
                row['variation.product.name'] = product.get('name', '')
                row['variation.product.product_attributes'] = product.get('product_attributes', [])
                row['variation.product.supplier_product_ids'] = product.get('supplier_product_ids', [])
            
            rows.append(row)

    # Convert to DataFrame
    df = pd.DataFrame(rows)
    print(f"\nData Structure:")
    print(f"  Entries from API: {len(entries_raw)}")
    print(f"  Rows to insert: {len(df)} (items expanded into separate rows)")
    print(f"  Total columns: {len(df.columns)}")
    
    return df.copy()

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
        'inserted_at','updated_at','variation_product_inserted_at'
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
        "is_hidden",
        "is_locked",
        "is_sell_negative_variation",
        "remain_quantity",
        "variations_warehouses_actual_remain_quantity",
        "variations_warehouses_pending_quantity",
        "variations_warehouses_remain_quantity",
        "variations_warehouses_returning_quantity",
        "variations_warehouses_total_quantity",
        "variations_warehouses_waiting_quantity"
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


def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_variations"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['variation_id'].nunique() if 'variation_id' in df.columns else len(df)
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
        print(f"  Unique entries: {unique_orders}")
        print(f"  Total rows (total entries): {total_rows}")
        
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")

def run_export(*, project_id=None, all_flag=True, start_date=None, end_date=None, max_pages=None, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
    # Determine date range based on three options:
    # 1. all_flag: No date filters
    # 2. Manual dates: Use provided start_date and end_date
    # 3. Default: Yesterday 00:00:00 to 23:59:59
    if all_flag:
        start_date_arg = None
        end_date_arg = None
    elif start_date or end_date:
        start_date_arg = start_date
        end_date_arg = end_date
    else:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")
    
    entries_raw = load_data()

    # Filter data by date based on inserted_at column
    entries_raw = filter_data_by_date(entries_raw, start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any orders
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(entries_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)
    df = normalize_id_strings(df)
    
    if dry_run:
        print(f"DRY RUN: {len(df)} rows ready for load (unique transfers: {df['variation_id'].nunique() if 'variation_id' in df.columns else len(df)})")
        print(df.head())
        return "Dry run complete", 200

    message = insert_to_bigquery(df, project_id=project_id)
    return message or "Success", 200

def main(argv=None):
    parser = argparse.ArgumentParser(description="Export Pancake POS entry data to BigQuery")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.set_defaults(All=False)  # Default behavior is yesterday's date range
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
    logging.info("Triggering Pancake variations data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500

if __name__ == "__main__":
    main()


# Placeholder for next edit
