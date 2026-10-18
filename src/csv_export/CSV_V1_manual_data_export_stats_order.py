#!/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/lsoul_document/.venv/bin/python3
import json
import argparse
import warnings
import requests
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
import pytz
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OutputPath = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv") #Path("G:/My Drive/03. CODE & DOCUMENTS/data_export_csv")

COLUMN_RENAME_MAP = {
            "Time.day": "inserted_at",
            "result.cod": "result_cod",
            "result.discount": "result_discount",
            "result.order_count": "result_order_count",
            "result.price": "result_price",
            "result.price_data": "result_price_data",
            "result.product_count": "result_product_count",
            "result.range": "result_range",
            "result.shipping_fee": "result_shipping_fee",
            "result.surcharge": "result_surcharge",
            "returned.cod": "returned_cod",
            "returned.discount": "returned_discount",
            "returned.is_returned": "returned_is_returned",
            "returned.order_count": "returned_order_count",
            "returned.price": "returned_price",
            "returned.price_data": "returned_price_data",
            "returned.product_count": "returned_product_count",
            "returned.range": "returned_range",
            "returned.shipping_fee": "returned_shipping_fee",
            "returned.surcharge": "returned_surcharge",
            "success.cod": "success_cod",
            "success.discount": "success_discount",
            "success.is_returned": "success_is_returned",
            "success.order_count": "success_order_count",
            "success.price": "success_price",
            "success.price_data": "success_price_data",
            "success.product_count": "success_product_count",
            "success.range": "success_range",
            "success.shipping_fee": "success_shipping_fee",
            "success.surcharge": "success_surcharge"
}


def parse_date_to_utc_datetime(date_string):
    """
    Convert Vietnam local time string to an aware UTC datetime.
    Returns None if input is empty.
    """
    if not date_string or date_string.strip() == "":
        return None

    try:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        dt_vietnam = vietnam_tz.localize(dt)
        return dt_vietnam.astimezone(pytz.UTC)
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")

def load_data(start_date=None, end_date=None):
    """
    Load stats order data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/analytics/sale"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000
    
    # Convert date strings to UTC datetimes (no Unix timestamp)
    start_datetime = parse_date_to_utc_datetime(start_date)
    end_datetime = parse_date_to_utc_datetime(end_date)

    print("Fetching data from API...")
    if start_datetime or end_datetime:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        if start_datetime:
            vietnam_start = start_datetime.astimezone(vietnam_tz)
            print(f"  Start date (Vietnam/Input): {start_date} → UTC: {start_datetime.strftime('%Y-%m-%d %H:%M:%S')}")
        if end_datetime:
            vietnam_end = end_datetime.astimezone(vietnam_tz)
            print(f"  End date (Vietnam/Input): {end_date} → UTC: {end_datetime.strftime('%Y-%m-%d %H:%M:%S')}")
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
                params['since'] = start_datetime.strftime("%Y-%m-%dT%H:%M:%S")
            if end_datetime:
                params['until'] = end_datetime.strftime("%Y-%m-%dT%H:%M:%S")

            response = requests.get(api_url, params=params, timeout=9999)
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
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    rows = []
    
    for entry in entries_raw:
        # Get all base variation-level fields (exclude nested objects)
        base_fields = {k: v for k, v in entry.items() if k not in ['result', 'returned', 'success']}
        
        # Get result object (single object, not a list)
        result = entry.get('result', {})
        
        # Get returned object (single object, not a list)
        returned = entry.get('returned', {})

        # Get success object (single object, not a list)
        success = entry.get('success', {})
        
        row = base_fields.copy()
        row['result.cod'] = result.get('cod', 0)
        row['result.discount'] = result.get('discount', 0)
        row['result.is_returned'] = result.get('is_returned', False)
        row['result.order_count'] = result.get('order_count', 0)
        row['result.price'] = result.get('price', 0)
        row['result.price_data'] = result.get('price_data', {})
        row['result.product_count'] = result.get('product_count', 0)
        row['result.range'] = result.get('range', '')
        row['result.shipping_fee'] = result.get('shipping_fee', 0)
        row['result.surcharge'] = result.get('surcharge', 0)
        row['returned.cod'] = returned.get('cod', 0)
        row['returned.discount'] = returned.get('discount', 0)
        row['returned.is_returned'] = returned.get('is_returned', False)
        row['returned.order_count'] = returned.get('order_count', 0)
        row['returned.price'] = returned.get('price', 0)
        row['returned.price_data'] = returned.get('price_data', {})
        row['returned.product_count'] = returned.get('product_count', 0)
        row['returned.range'] = returned.get('range', '')
        row['returned.shipping_fee'] = returned.get('shipping_fee', 0)
        row['returned.surcharge'] = returned.get('surcharge', 0)
        row['success.cod'] = success.get('cod', 0)
        row['success.discount'] = success.get('discount', 0)
        row['success.is_returned'] = success.get('is_returned', False)
        row['success.order_count'] = success.get('order_count', 0)
        row['success.price'] = success.get('price', 0)
        row['success.price_data'] = success.get('price_data', {})
        row['success.product_count'] = success.get('product_count', 0)
        row['success.range'] = success.get('range', '')
        row['success.shipping_fee'] = success.get('shipping_fee', 0)
        row['success.surcharge'] = success.get('surcharge', 0)

        rows.append(row)

    # Convert to DataFrame
    df = pd.DataFrame(rows)
    print(f"\nData Structure:")
    print(f"  Entries from API: {len(entries_raw)}")
    print(f"  Rows to insert: {len(df)} (items expanded into separate rows)")
    print(f"  Total columns: {len(df.columns)}")
    
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

def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    for col in df.columns:
        df[col] = df[col].astype(str).replace(['nan', '{}','[]'], '')
    return df

def convert_dates_to_timestamp(df):
    date_columns = [
        'inserted_at'
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
        print(f"  {i:3d}. {col} -> {new_name}")
    print(f"\nTotal: {len(df.columns)} columns\n")

def export_data(df, output_file):
    # Convert all columns to object type to preserve empty strings
    for col in df.columns:
        df[col] = df[col].astype('object')
    # Export with UTF-8 encoding (with BOM for better Excel compatibility)
    # BOM (Byte Order Mark) helps Excel properly detect UTF-8 encoding for Vietnamese characters
    df.to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS ecom product data to BigQuery")
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
    
    entries_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
   # Check if there are any entries
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(entries_raw)
    if args.list:
        list_columns(df)
        return
    
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = clean_empty_json(df)

    # Determine output filename if not provided
    output_dir = OutputPath
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if args.output:
        output_file = output_dir / args.output
    else:
        now_ts = datetime.now().strftime('%Y%m%d%H%M%S')
        output_file = output_dir / f"pancake_raw_stats_order_{now_ts}.csv"

    export_data(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")

    
if __name__ == "__main__":
    main()

# Placeholder for next edit
