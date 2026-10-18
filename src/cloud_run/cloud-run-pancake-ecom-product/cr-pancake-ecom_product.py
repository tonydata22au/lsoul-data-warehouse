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
    #    
            "id": "ecom_product_id",
            #"linked_product_custom_id": "linked_product_custom_id",
            "marketplace_id": "marketplace_id",
            "marketplace_shop_name": "marketplace_shop_name",
            "name": "ecom_title",
            #"price": "price", #value returns 0
            "sku": "ecom_product_sku",
            "warehouse" : "warehouse",
            "variations_id": "variations_id",
            #"variations_images": "variations_images",
            "variations_linked_product_custom_id": "variations_linked_product_custom_id",
            "variations_linked_variation_custom_id": "variations_linked_variation_custom_id",
            "variations_linked_variation_fields": "variations_linked_variation_fields",
            "variations_linked_variation_price": "variations_linked_variation_price",
            "variations_name": "variations_name",
            "variations_price": "variations_price",
            "variations_quantity": "variations_quantity",
            "variations_sku": "variations_sku",
           
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

def load_data(start_date=None, end_date=None, max_pages=None):
    """
    Load product data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/marketplace/products"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_ecom_products = []
    page = 1
    page_size = 1000
    
    # Convert date strings to Unix timestamps
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
                'page_size': page_size
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['startDateTime'] = start_datetime
            if end_datetime:
                params['endDateTime'] = end_datetime

            response = requests.get(api_url, params=params, timeout=69)
            response.raise_for_status()
            payload = response.json()
            
            ecom_products = payload.get("data", [])
            if not ecom_products:
                break
            
            all_ecom_products.extend(ecom_products)
            total_pages = payload.get("total_pages", 1)
            print(f"  Fetched page {page}/{total_pages}: {len(ecom_products)} products (total: {len(all_ecom_products)})")

            # Check if there are more pages
            if len(ecom_products) < page_size and page >= total_pages:
                break
            
            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")

    print(f"Successfully fetched {len(all_ecom_products)} ecom products from API\n")
    return all_ecom_products


def flatten_data(ecom_products_raw):
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    # Check if ecom products have variations (array that needs to be exploded into rows)
    has_items = any(isinstance(o.get("variations"), list) and o.get("variations") for o in ecom_products_raw)
    
    if has_items:
        # Normalize with items as record_path (each item becomes a row)
        # and include all order-level fields as meta
        df = json_normalize(
            ecom_products_raw,
            record_path="variations",
            meta=[col for col in ecom_products_raw[0].keys() if col != "variations"],  # Include all parent columns
            record_prefix="variations_",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        print(f"\nData Structure:")
        print(f"  Ecom products from API: {len(ecom_products_raw)}")
        print(f"  Product variations (rows): {len(df)}")
        print(f"  Note: Each product variation creates a separate row in the table")
        print(f"  Variation-level columns: {len([c for c in df.columns if c.startswith('variations_')])}")
        print(f"  Product-level columns: {len([c for c in df.columns if not c.startswith('variations_')])}")
    else:
        df = json_normalize(ecom_products_raw, sep=".", errors="ignore")

        print(f"\nData Structure:")
        print(f"  Ecom products from API: {len(ecom_products_raw)}")
        print(f"  Rows to insert: {len(df)}")

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
            df[col] = str_vals.map({'True': 1, 'False': 0})
            # Rename column to have is_ prefix if it doesn't already
            if not col.startswith('is_'):
                new_col = f"is_{col}"
                df = df.rename(columns={col: new_col})
    
    return df

def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    for col in df.columns:
        df[col] = df[col].astype(str).replace(['nan', '{}','[]'], '')
    return df


def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_ecom_product"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['ecom_product_id'].nunique() if 'ecom_product_id' in df.columns else len(df)
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
        print(f"  Unique orders: {unique_orders}")
        print(f"  Total rows (order items): {total_rows}")
        
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

    ecom_products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg, max_pages=max_pages)
    
    # Check if there are any products
    if not ecom_products_raw or len(ecom_products_raw) == 0:
        print("0 entry found. No data to export.")
        return

    df = flatten_data(ecom_products_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = clean_empty_json(df)

    if dry_run:
        print(f"DRY RUN: {len(df)} rows ready for load (unique transfers: {df['ecom_product_id'].nunique() if 'ecom_product_id' in df.columns else len(df)})")
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
    logging.info("Triggering Pancake order data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500

if __name__ == "__main__":
    main()