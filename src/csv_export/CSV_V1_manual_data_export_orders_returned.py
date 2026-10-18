#!/usr/bin/env python3
import json
import argparse
import warnings
import pytz
import requests
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OutputPath = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv") #Path("G:/My Drive/03. CODE & DOCUMENTS/data_export_csv") 


COLUMN_RENAME_MAP = {
            "inserted_at": "inserted_at",
            "display_id": "display_id",
            "discount": "discount",
            "discount_from_order_to_returned": "discount_from_order_to_returned",
            "status": "status",
            "order_to_returned.id": "original_order_id",
            "order.id": "returned_order_id", 
            "order_to_returned.order_sources_name": "order_to_returned_order_sources_name",
            "order_to_returned.order_sources": "order_to_returned_order_sources",
            "order_to_returned.warehouse_id": "order_to_returned_warehouse_id",
            "order_to_returned.exchange_value": "order_to_returned_exchange_value",
            "order_to_returned.status": "order_to_returned_status",
            "order_to_returned.total_price": "order_to_returned_total_price",
            "order_to_returned.updated_at": "order_to_returned_updated_at",
            "order_to_returned.exchange_payment": "order_to_returned_exchange_payment",
            "order_to_returned.returned_reason": "order_to_returned_returned_reason",
            "order_to_returned.order_currency": "order_to_returned_order_currency",
            "order_to_returned.note": "order_to_returned_note",
            "updated_at": "updated_at",
            "bill_phone_number": "bill_phone_number",
            "order_id": "id",
            "order_id_to_returned": "order_id_to_returned",
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
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    # Check if orders have items (array that needs to be exploded into rows)
    has_items = any(isinstance(o.get("order_to_returned"), list) and o.get("order_to_returned") for o in entries_raw)
    
    if has_items:
        # Normalize with items as record_path (each item becomes a row)
        # and include all order-level fields as meta
        df = json_normalize(
            entries_raw,
            record_path="order_to_returned",
            meta=[
            "id","order_sources_name","order_sources","warehouse_id","exchange_value","status","total_price",
            "updated_at","exchange_payment","returned_reason","order_currency","note",   
            ],
            record_prefix="order_to_returned.",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        
        print(f"\nData Structure:")
        print(f"  Returned orders from API: {len(entries_raw)}")
        print(f"  Order to returned (rows): {len(df)}")
        print(f"  Order to returned-level columns: {len([c for c in df.columns if c.startswith('order_to_returned.')])}")
        print(f"  Order-level columns: {len([c for c in df.columns if not c.startswith('order_to_returned.')])}")
    else:
        # No items, just normalize the order data with all nested objects flattened
        df = json_normalize(entries_raw, sep=".", errors="ignore")
        
        print(f"\nData Structure:")
        print(f"  Orders from API: {len(entries_raw)}")
        print(f"  Rows to insert: {len(df)}")
    
    return df.copy()

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

def export_data(df, output_file):
    # Convert all columns to object type to preserve empty strings
    for col in df.columns:
        df[col] = df[col].astype('object')
    # Export with UTF-8 encoding (with BOM for better Excel compatibility)
    # BOM helps Excel properly detect UTF-8 encoding for Vietnamese characters
    df.to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS order data to BigQuery or CSV")
    parser.add_argument("--list", action="store_true", help="List all available columns")
    parser.add_argument("--output", default=None, help="Output CSV filename (optional). If provided, also exports to CSV")
    parser.add_argument("--csv-only", action="store_true", help="Export to CSV only, skip BigQuery insert")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    
    args = parser.parse_args()
    
    # Determine date range based on three options:
    # 1. --All flag: No date filters
    # 2. Manual dates: Use provided --start-date and --end-date
    # 3. Default: Yesterday 00:00:00 to 23:59:59
    if args.All:
        start_date_arg = None
        end_date_arg = None
    elif args.start_date or args.end_date:
        start_date_arg = args.start_date
        end_date_arg = args.end_date
    else:
        # Default: Yesterday in Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")
    
    entries_raw = load_data()

   # Check if there are any entries
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    # Filter data by date based on inserted_at column
    entries_raw = filter_data_by_date(entries_raw, start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any entries after filtering
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

    # Ensure final CSV contains only the columns defined in COLUMN_RENAME_MAP,
    # in the same order. Missing columns will be filled with empty strings.
    final_columns = list(COLUMN_RENAME_MAP.values())
    df = df.reindex(columns=final_columns, fill_value='')

     # Determine output filename if not provided
    output_dir = OutputPath
    output_dir.mkdir(parents=True, exist_ok=True)

    # Determine output filename if not provided
    if args.output:
        output_file = output_dir / args.output
    else:
        now_ts = datetime.now().strftime('%Y%m%d%H%M%S')
        output_file = output_dir / f"pancake_raw_orders_returned_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()

# Placeholder for next edit
