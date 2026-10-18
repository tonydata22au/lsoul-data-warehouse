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
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logging.basicConfig(level=logging.INFO)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

COLUMN_RENAME_MAP = {
    # Maps from flatten_data() output columns to desired final names
    
            "inserted_at": "inserted_at",
            "id": "warehouse_transfer_id",
            "display_id": "warehouse_transfer_display_id",
            "status": "status",
            "updated_status_at": "updated_status_at",
            "from_warehouse_id": "from_warehouse_id",
            "from_warehouse_name": "from_warehouse_name",
            "to_warehouse_id": "to_warehouse_id",
            "to_warehouse_name": "to_warehouse_name",
            "creator.name": "creator_name",
            "shipping_fee": "shipping_fee",
            "total_quantity": "total_quantity",
                    "items.display_id": "items_display_id",
                    "items.id": "items_id",
                    "items.product_display_id": "items_product_display_id",
                    "items.product_name": "items_product_name",
                    "items.quantity": "items_quantity",
                    "items.variation_display_id": "items_variation_display_id",
                    "items.variation_id": "items_variation_id",
                        "items.variation.fields": "items_variation_fields",
                        "items.variation.images": "items_variation_images",
                        "items.variation.inserted_at": "items_variation_inserted_at",
                        "items.variation.is_hidden": "items_variation_is_hidden",
                        "items.variation.is_locked": "items_variation_is_locked",
                        "items.variation.is_removed": "items_variation_is_removed",
                        "items.variation.is_sell_negative_variation": "items_variation_is_sell_negative_variation",
                        "items.variation.last_imported_price": "items_variation_last_imported_price",
                        "items.variation.price_at_counter": "items_variation_price_at_counter",
                        "items.variation.product_id": "items_variation_product_id",
                        "items.variation.retail_price": "items_variation_retail_price",
                        "items.variation.retail_price_after_discount": "items_variation_retail_price_after_discount",
                        "items.variation.wholesale_price": "items_variation_wholesale_price",
                            "items.variation.product.display_id": "items_variation_product_display_id",
                            "items.variation.product.inserted_at": "items_variation_product_inserted_at",
                            "items.variation.product.name": "items_variation_product_name",
                            "items.variation.product.product_attributes":  "items_variation_product_attributes",
                            "items.variation.product.supplier_product_ids": "items_variation_product_supplier_product_ids",           
}

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
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/transfers"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000
    status = 2
    
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
        if max_pages and page > max_pages:
            print(f"  Reached max_pages={max_pages}, stopping fetch")
            break
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
                'status': status,
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['startDate'] = start_datetime
            if end_datetime:
                params['endDate'] = end_datetime

            response = requests.get(api_url, params=params, timeout=169, verify=False)
            response.raise_for_status()
            payload = response.json()
            
            entries = payload.get("data", [])
            if not entries:
                break
            
            all_entries.extend(entries)
            total_pages = payload.get("total_pages", 1)
            print(f"  Fetched page {page}/{total_pages}: {len(entries)} entries (total: {len(all_entries)})")
            
            # Check if there are more pages
            if len(entries) < page_size and page >= total_pages:
                break
            
            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"✓ Successfully fetched {len(all_entries)} entries from API\n")
    return all_entries


def flatten_data(entries_raw):
    """Flatten warehouse transfer data, expanding items into separate rows with all nested fields extracted."""
    
    rows = []
    
    for entry in entries_raw:
        # Get all base transfer-level fields
        base_fields = {k: v for k, v in entry.items() if k != 'items'}
        
        # Check if items exist and is a list
        items_list = entry.get('items', [])
        
        if isinstance(items_list, list) and len(items_list) > 0:
            # Expand each item into separate rows
            for item in items_list:
                row = base_fields.copy()
                
                # Extract item-level fields
                row['items.display_id'] = item.get('display_id')
                row['items.id'] = item.get('id')
                row['items.product_display_id'] = item.get('product_display_id')
                row['items.product_name'] = item.get('product_name')
                row['items.quantity'] = item.get('quantity')
                
                # Extract variation fields
                variation = item.get('variation', {})
                row['items.variation_display_id'] = variation.get('display_id')
                row['items.variation_id'] = variation.get('id')
                row['items.variation.fields'] = variation.get('fields')
                row['items.variation.id'] = variation.get('id')
                row['items.variation.images'] = variation.get('images')
                row['items.variation.inserted_at'] = variation.get('inserted_at')
                row['items.variation.is_hidden'] = variation.get('is_hidden')
                row['items.variation.is_locked'] = variation.get('is_locked')
                row['items.variation.is_removed'] = variation.get('is_removed')
                row['items.variation.is_sell_negative_variation'] = variation.get('is_sell_negative_variation')
                row['items.variation.last_imported_price'] = variation.get('last_imported_price')
                row['items.variation.price_at_counter'] = variation.get('price_at_counter')
                row['items.variation.product_id'] = variation.get('product_id')
                row['items.variation.retail_price'] = variation.get('retail_price')
                row['items.variation.retail_price_after_discount'] = variation.get('retail_price_after_discount')
                row['items.variation.wholesale_price'] = variation.get('wholesale_price')
                
                # Extract nested product fields
                product = variation.get('product', {})
                row['items.variation.product.display_id'] = product.get('display_id')
                row['items.variation.product.inserted_at'] = product.get('inserted_at')
                row['items.variation.product.name'] = product.get('name')
                row['items.variation.product.product_attributes'] = product.get('product_attributes')
                row['items.variation.product.supplier_product_ids'] = product.get('supplier_product_ids')
                
                rows.append(row)
        else:
            # No items, just add the base entry
            rows.append(base_fields)
    
    # Convert to DataFrame
    df = pd.DataFrame(rows)
    
    print(f"\nData Structure:")
    print(f"  Entries from API: {len(entries_raw)}")
    print(f"  Rows to insert: {len(df)} (items expanded into separate rows)")
    print(f"  Total columns: {len(df.columns)}")
    
    # Extract nested fields from 'creator' object if it exists
    if 'creator' in df.columns:
        df['creator.name'] = df['creator'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)
        df['creator.id'] = df['creator'].apply(lambda x: x.get('id') if isinstance(x, dict) else None)
        df['creator.avatar_url'] = df['creator'].apply(lambda x: x.get('avatar_url') if isinstance(x, dict) else None)
        df['creator.fb_id'] = df['creator'].apply(lambda x: x.get('fb_id') if isinstance(x, dict) else None)
    
    return df.copy()

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
    """Convert date strings to YYYYMMDDHHMMSS format in Vietnam time (UTC+7)."""
    date_columns = [
        'inserted_at', 'updated_status_at', 'items_variation_inserted_at', 'items_variation_product_inserted_at'
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

def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_warehouse_transfers_completed"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['warehouse_transfer_id'].nunique() if 'warehouse_transfer_id' in df.columns else len(df)
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

        message = (
            f"✓ Successfully loaded {load_job.output_rows} rows to {dataset_id}.{table_id} [{load_job.job_id}]\n"
            f"Unique entries: {unique_orders}\n"
            f"Total rows (total entries): {total_rows}"
        )
        print(message)
        return message

    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")

def run_export(*, project_id=None, all_flag=False, start_date=None, end_date=None, max_pages=None, dry_run=False):
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

    entries_raw = load_data(start_date=start_date_arg, end_date=end_date_arg, max_pages=max_pages)

    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return "No data", 200
    
    df = flatten_data(entries_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)

    if dry_run:
        print(f"DRY RUN: {len(df)} rows ready for load (unique transfers: {df['warehouse_transfer_id'].nunique() if 'warehouse_transfer_id' in df.columns else len(df)})")
        print(df.head())
        return "Dry run complete", 200

    message = insert_to_bigquery(df, project_id=project_id)
    return message or "Success", 200


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export Pancake POS entry data to BigQuery")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
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
    logging.info("Triggering Pancake warehouse transfer data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500

    
if __name__ == "__main__":
    main()

