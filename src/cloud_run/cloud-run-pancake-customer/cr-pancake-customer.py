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

            # Core identity & audit
            "id": "entry_id",
            "inserted_at": "inserted_at",
            "updated_at": "updated_at",
            "customer_id": "customer_id",
            "username": "username",
            "tags": "tags",
            # Contact & demographics
            "fb_id": "fb_id",

            

            # Status, level & ownership
            "is_block": "is_block",
            #"user_block_id": "user_block_id",
            #"level": "level",
            #"is_discount_by_level": "is_discount_by_level",
            "assigned_user_id": "assigned_user_id",
            "creator.name": "creator_name",
            "creator_id": "creator_id",

           
            "currency": "currency",

            # Order stats
            "order_count": "order_count",
            "succeed_order_count": "succeed_order_count",
            "returned_order_count": "returned_order_count",
            "purchased_amount": "purchased_amount",
            "last_order_at": "last_order_at",
            "order_sources": "order_sources",

            # Address (flattened)
            "shop_customer_addresses.id": "shop_customer_addresses_id",
            "shop_customer_addresses.country_code": "shop_customer_addresses_country_code",
            "shop_customer_addresses.province_id": "shop_customer_addresses_province_id",
            "shop_customer_addresses.commune_id": "shop_customer_addresses_commune_id",
            #"conversation_tags": "conversation_tags",

            #"name": "T***g P***",
            #"count_referrals": 0,
            #"phone_numbers":
            #"tags": [],
            #"date_of_birth": null,
            #"is_adjust_debts": null,
            #"current_debts": 0,
            #"active_levera_pay": false
            #"notes": [],
            #"conversation_link": null,
            #"emails": "emails",
            #"gender": "gender",
            #"user_block_id": "user_block_id",
            #"level": "level",
            #"used_reward_point": "used_reward_point",
            #"referral_code": "referral_code",
            #"reward_point": "reward_point",
            #"total_amount_referred": "total_amount_referred",
            #"list_voucher": "list_voucher",
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

def load_data(start_date=None, end_date=None,max_pages=None):
    """
    Load customer data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/customers"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000
    
     # Convert date strings to Unix timestamps
    start_datetime = parse_date_to_unix(start_date)
    end_datetime = parse_date_to_unix(end_date)

    print("Fetching data from API...")
    if start_datetime or end_datetime:
        if start_datetime:
            print(f"  Start date: {datetime.fromtimestamp(start_datetime).strftime('%Y-%m-%d %H:%M:%S')} - {parse_date_to_unix(start_date)}")
        if end_datetime:
            print(f"  End date: {datetime.fromtimestamp(end_datetime).strftime('%Y-%m-%d %H:%M:%S')} - {parse_date_to_unix(end_date)}")
    else:
        print(f"  No date filters applied - fetching all data")
    
    while True:
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['start_time_updated_at'] = start_datetime
            if end_datetime:
                params['end_time_updated_at'] = end_datetime

            response = requests.get(api_url, params=params, timeout=999999)
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
            
            if max_pages and page >= max_pages:
                break

            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"✓ Successfully fetched {len(all_entries)} entries from API\n")
    return all_entries


def flatten_data(entries_raw):
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    # Check if orders have items (array that needs to be exploded into rows)
    # Items are nested inside 'order' object as 'order.items'
    has_items = any(isinstance(o.get("shop_customer_addresses"), list) and o.get("shop_customer_addresses") for o in entries_raw)
    
    if has_items:
        # Normalize with items as record_path (each item becomes a row)
        # and include all order-level fields as meta
        df = json_normalize(
            entries_raw,
            record_path="shop_customer_addresses",
            meta=[col for col in entries_raw[0].keys() if col != "shop_customer_addresses"],
            record_prefix="shop_customer_addresses.",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        print(f"\nData Structure:")
        print(f"  Entries from API: {len(entries_raw)}")
        print(f"  Customer record (rows): {len(df)}")
        print(f"  Note: Each customer record creates a separate row in the table")
        print(f"  Customer-level columns: {len([c for c in df.columns if c.startswith('shop_customer_addresses.')])}")
    else:
        # No items, just normalize the order data with all nested objects flattened
        df = json_normalize(entries_raw, sep=".", errors="ignore")
        print(f"\nData Structure:")
        print(f"  Entries from API: {len(entries_raw)}")
        print(f"  Rows to insert: {len(df)}")
    
    # Extract nested fields from 'user' object if it exists
    if 'creator' in df.columns:
        df['creator.name'] = df['creator'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)

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
    date_columns = [
        'inserted_at', 'updated_at','last_order_at'
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
        "shop_customer_addresses_country_code"
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


def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_customer"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['entry_id'].nunique() if 'entry_id' in df.columns else len(df)
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
        print(f"  Unique customers: {unique_orders}")
        print(f"  Total rows (customer records): {total_rows}")
        
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")


def run_export(*, project_id=None, all_flag=False, start_date=None, end_date=None, max_pages=None, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
     # Determine date range based on three options:
    # 1. --All flag: No date filters
    # 2. Manual dates: Use provided --start-date and --end-date
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
    
   # Check if there are any orders
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return "0 entry found. No data to export.", 200
    
    df = flatten_data(entries_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)
    df = normalize_id_strings(df)
    
    if dry_run:
        print(f"DRY RUN: {len(df)} rows ready for load (unique transfers: {df['entry_id'].nunique() if 'entry_id' in df.columns else len(df)})")
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
    logging.info("Triggering Pancake customer data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500
    
if __name__ == "__main__":
    main()

# Placeholder for next edit
