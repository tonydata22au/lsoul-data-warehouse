#!/usr/bin/env python3
import argparse
import os
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
            "inserted_at": "inserted_at",
            "display_id": "display_id",
            "status": "status",
            "bill_full_name": "bill_full_name",
            "customer.id": "customer_id",
            "updated_at": "updated_at",
            "creator_id": "creator_id",
            "order.id": "order_id",  
            "order_to_returned.id": "order_to_returned_id"
}


def load_data():
    """Load data from Pancake API with pagination and minimal per-request overhead."""

    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/orders_returned"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000

    print("Fetching data from API...")
    
    while True:
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size
            }
        
            response = requests.get(api_url, params=params, timeout=99999)
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
    
    print(f"Successfully fetched {len(all_entries)} entries from API\n")
    return all_entries

def filter_data_by_date(entries, start_date=None, end_date=None):
    """
    Filter entries based on inserted_at.

    User-provided start/end are in Vietnam time; they are converted to UTC for comparison
    against inserted_at, which the API returns in UTC (or assumed UTC if naive).
    """
    if not start_date and not end_date:
        print("No date filters applied - using all data")
        return entries

    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')

    start_dt_utc = None
    end_dt_utc = None
    if start_date:
        start_dt_vn = vietnam_tz.localize(datetime.strptime(start_date, "%Y-%m-%dT%H:%M:%S"))
        start_dt_utc = start_dt_vn.astimezone(pytz.utc)
    if end_date:
        end_dt_vn = vietnam_tz.localize(datetime.strptime(end_date, "%Y-%m-%dT%H:%M:%S"))
        end_dt_utc = end_dt_vn.astimezone(pytz.utc)

    print("Filtering data by inserted_at (user input VN → UTC)...")
    if start_dt_utc:
        print(f"  Start (VN): {start_dt_vn.strftime('%Y-%m-%d %H:%M:%S %Z')} | UTC: {start_dt_utc.strftime('%Y-%m-%d %H:%M:%S %Z')}")
    if end_dt_utc:
        print(f"  End   (VN): {end_dt_vn.strftime('%Y-%m-%d %H:%M:%S %Z')} | UTC: {end_dt_utc.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    def parse_to_utc(ts: str):
        if not ts:
            return None
        try:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        except ValueError:
            if "." in ts:
                try:
                    dt = datetime.strptime(ts.split(".")[0], "%Y-%m-%dT%H:%M:%S")
                except ValueError:
                    return None
            else:
                try:
                    dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S")
                except ValueError:
                    return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=pytz.utc)
        return dt.astimezone(pytz.utc)

    filtered_entries = []
    for entry in entries:
        entry_dt = parse_to_utc(entry.get("inserted_at"))
        if not entry_dt:
            continue

        if start_dt_utc and entry_dt < start_dt_utc:
            continue
        if end_dt_utc and entry_dt > end_dt_utc:
            continue

        filtered_entries.append(entry)

    print(f"  Filtered: {len(entries)} → {len(filtered_entries)} entries\n")
    return filtered_entries

def flatten_data(entries_raw):
    """Flatten order data without exploding items; keep order-level fields only.

    Also collapses nested list fields we care about (e.g., order_to_returned.change_by_orders)
    to their first element so dot-path columns in COLUMN_RENAME_MAP materialize.
    """

    normalized_orders = []
    for order in entries_raw:
        # Shallow copy to avoid mutating original payload
        order_copy = dict(order)

        # Normalize creator if API returns a list; take the first entry
        creator_val = order_copy.get("creator")
        if isinstance(creator_val, list) and creator_val:
            first_creator = creator_val[0]
            if isinstance(first_creator, dict):
                order_copy["creator"] = first_creator

        otr = order_copy.get("order_to_returned")
        if isinstance(otr, dict):
            otr_copy = dict(otr)
            cbo = otr_copy.get("change_by_orders")
            # Collapse list to first entry so json_normalize can expose dotted fields
            if isinstance(cbo, list) and cbo:
                first_cbo = cbo[0]
                if isinstance(first_cbo, dict):
                    otr_copy["change_by_orders"] = first_cbo
            order_copy["order_to_returned"] = otr_copy

        normalized_orders.append(order_copy)

    df = json_normalize(normalized_orders, sep=".", errors="ignore")

    print("\nData Structure:")
    print(f"  Orders from API: {len(entries_raw)}")
    print(f"  Rows to insert: {len(df)}")

    return df

def rename_and_reorder_columns(df):
    # Include all columns from COLUMN_RENAME_MAP, creating empty columns for missing data
    # This ensures consistent column structure across all exports
    new_df_dict = {}
    
    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
        else:
            # Create empty column for missing fields from API
            new_df_dict[new_col] = ''
    
    result_df = pd.DataFrame(new_df_dict)
    # Cast all normalized columns to string for schema consistency
    for col in result_df.columns:
        result_df[col] = result_df[col].astype(str)
    return result_df


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


def convert_dates_to_timestamp(df):
    date_columns = [
        'inserted_at', 'updated_at'
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
    

def list_columns(df):
    print("\nAvailable columns:")
    for i, col in enumerate(df.columns, 1):
        new_name = COLUMN_RENAME_MAP.get(col, col)
        print(f"  {i:3d}. {col} → {new_name}")
    print(f"\nTotal: {len(df.columns)} columns\n")

def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    # Only process object/string columns to preserve numeric types
    for col in df.columns:
        if df[col].dtype == 'object':
            df[col] = df[col].astype(str).replace(['nan', '{}','[]','None'], '')
    return df


def cast_columns_to_string(df):
    """Ensure all columns defined in COLUMN_RENAME_MAP are cast to string."""
    target_cols = list(COLUMN_RENAME_MAP.values())
    for col in target_cols:
        if col in df.columns:
            df[col] = df[col].astype(str)
    return df


def normalize_id_strings(df):
    """Normalize ID-like columns to remove float-ish suffixes (e.g., 123456.0 → 123456)."""
    id_like_cols = [
        "order_id",
        "order_to_returned_id",
        "display_id",
        "customer_id",
        "creator_id",
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

def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_orders_returned"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['display_id'].nunique() if 'display_id' in df.columns else len(df)
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

def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS order data to BigQuery or CSV")
    parser.add_argument("--list", action="store_true", help="List all available columns")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    
    args = parser.parse_args()
    
    # Determine date range based on three options:
    # 1. --All flag: No date filters
    # 2. Manual dates: Use provided --start-date and --end-date (VN time inputs)
    # 3. Default: Last 30 days ending yesterday (VN time)
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    if args.All:
        start_date_arg = None
        end_date_arg = None
    elif args.start_date or args.end_date:
        start_date_arg = args.start_date
        end_date_arg = args.end_date
    else:
        now_vn = datetime.now(vietnam_tz)
        end_vn = (now_vn - timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=0)
        start_vn = end_vn - timedelta(days=30)
        start_date_arg = start_vn.strftime("%Y-%m-%dT%H:%M:%S")
        end_date_arg = end_vn.strftime("%Y-%m-%dT%H:%M:%S")

    entries_raw = load_data()

   # Check if there are any products
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    # Filter data by date based on inserted_at column
    entries_raw = filter_data_by_date(entries_raw, start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any products after filtering
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found after date filtering. No data to export.")
        return
    
    df = flatten_data(entries_raw)
    
    if args.list:
        list_columns(df)
        return
    
    
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)
    df = cast_columns_to_string(df)
    df = normalize_id_strings(df)

    insert_to_bigquery(df, project_id=args.project_id)

if __name__ == "__main__":
    main()

# Placeholder for next edit
