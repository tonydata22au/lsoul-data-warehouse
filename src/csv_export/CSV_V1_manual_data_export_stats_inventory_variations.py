#!/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/lsoul_document/.venv/bin/python3
import argparse
import warnings
import requests
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OutputPath = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv") #Path("G:/My Drive/03. CODE & DOCUMENTS/data_export_csv") 


COLUMN_RENAME_MAP = {
            "begin_inventory": "begin_inventory",
            "begin_inventory_value": "begin_inventory_value",
            "end_inventory": "end_inventory",
            "end_inventory_value": "end_inventory_value",
            "id": "stat_id",
            "purchase_export": "purchase_export",
            "purchase_import": "purchase_import",
            "return_import": "return_import",
            "sell_export": "sell_export",
            "stocktaking_export": "stocktaking_export",
            "stocktaking_import": "stocktaking_import",
            "total_export": "total_export",
            "total_export_value": "total_export_value",
            "total_import": "total_import",
            "total_import_value": "total_import_value",
            "transfer_export": "transfer_export",
            "transfer_import": "transfer_import",
            "variation.id" : "variation_id",
            "variation.custom_id": "variation_custom_id",
            "variation.display_id": "variation_display_id",
            "variation.fields": "variation_fields",
            "variation.product_id": "variation_product_id",
            "variation.product.custom_id": "variation_product_custom_id",
            "variation.product.display_id": "variation_product_display_id",
            "variation.product.inserted_at": "product_inserted_at",
            "variation.product.name": "variation_product_name",
            
}

def parse_date_to_unix(date_string):
    """
    Convert Vietnam local time (naive string) to Unix timestamp in UTC.
    Accepts an int/float (already a timestamp) and returns it unchanged.
    """
    if date_string is None:
        return None
    if isinstance(date_string, (int, float)):
        return int(date_string)
    if not isinstance(date_string, str) or date_string.strip() == "":
        return None

    try:
        dt_local = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=ZoneInfo("Asia/Ho_Chi_Minh"))
        dt_utc = dt_local.astimezone(timezone.utc)
        return int(dt_utc.timestamp())
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")


def ts_to_vn_string(ts_value):
    return datetime.fromtimestamp(ts_value, tz=timezone.utc).astimezone(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%Y-%m-%d %H:%M:%S %Z")


def build_daily_ranges(start_date_str, end_date_str):
    if not start_date_str or not end_date_str:
        raise ValueError("--insert_each_day requires both --start-date and --end-date")

    tz = ZoneInfo("Asia/Ho_Chi_Minh")
    start_dt = datetime.strptime(start_date_str, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=tz)
    end_dt = datetime.strptime(end_date_str, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=tz)

    if end_dt < start_dt:
        raise ValueError("end-date must be on or after start-date")

    ranges = []
    current_date = start_dt.date()
    end_date_only = end_dt.date()

    while current_date <= end_date_only:
        day_start = datetime.combine(current_date, time(0, 0, 0), tzinfo=tz)
        day_end = datetime.combine(current_date, time(23, 59, 59), tzinfo=tz)
        if day_end > end_dt:
            day_end = end_dt

        ranges.append((int(day_start.astimezone(timezone.utc).timestamp()), int(day_end.astimezone(timezone.utc).timestamp())))
        current_date += timedelta(days=1)

    return ranges

def load_data(start_date=None, end_date=None, label=None):
    """
    Load inventory data by variation from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/inventory_analytics/inventory"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000
    type_param = 'actual'
    
     # Convert date strings to Unix timestamps
    start_datetime = parse_date_to_unix(start_date)
    end_datetime = parse_date_to_unix(end_date)

    print(f"Fetching data from API{f' ({label})' if label else ''}...")
    if start_datetime or end_datetime:
        if start_datetime:
            print(f"  Start date: {ts_to_vn_string(start_datetime)} (UTC ts: {parse_date_to_unix(start_date)})")
        if end_datetime:
            print(f"  End date: {ts_to_vn_string(end_datetime)} (UTC ts: {parse_date_to_unix(end_date)})")
    else:
        print(f"  No date filters applied - fetching all data")
    
    while True:
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
                'type': type_param,
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['startDate'] = start_datetime
            if end_datetime:
                params['endDate'] = end_datetime

            response = requests.get(api_url, params=params, timeout=169)
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
        # Get all base transfer-level fields
        base_fields = {k: v for k, v in entry.items() if k != 'variation'}
        
        # Normalize variation payload: it can be a list or a single dict
        variation_payload = entry.get('variation', {})
        if isinstance(variation_payload, list):
            items_list = variation_payload
        elif isinstance(variation_payload, dict) and len(variation_payload) > 0:
            items_list = [variation_payload]
        else:
            items_list = []
        
        if items_list:
            # Expand each item into separate rows
            for item in items_list:
                row = base_fields.copy()
                # Extract variation-level fields
                row['variation.id'] = item.get('id')
                row['variation.custom_id'] = item.get('custom_id')
                row['variation.display_id'] = item.get('display_id')
                row['variation.fields'] = item.get('fields')
                row['variation.product_id'] = item.get('product_id')
                
                # Extract product-level fields
                product = item.get('product', {})
                row['variation.product.custom_id'] = product.get('custom_id')
                row['variation.product.display_id'] = product.get('display_id')
                row['variation.product.inserted_at'] = product.get('inserted_at')
                row['variation.product.name'] = product.get('name')

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
        'product_inserted_at'
    ]
    
    for col in date_columns:
        if col in df.columns:
            try:
                df[col] = pd.to_datetime(df[col]).dt.strftime('%Y%m%d%H%M%S')
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

def list_columns(df):
    print("\nAvailable columns:")
    for i, col in enumerate(df.columns, 1):
        new_name = COLUMN_RENAME_MAP.get(col, col)
        print(f"  {i:3d}. {col} → {new_name}")
    print(f"\nTotal: {len(df.columns)} columns\n")

def export_data(df, output_file):
    # Convert all columns to object type to preserve empty strings
    for col in df.columns:
        df[col] = df[col].astype('object')
    # Export with UTF-8 encoding (with BOM for better Excel compatibility)
    # BOM helps Excel properly detect UTF-8 encoding for Vietnamese characters
    df.to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS order data to BigQuery")
    parser.add_argument("--list", action="store_true", help="List all available columns")
    parser.add_argument("--output", default=None, help="Output CSV filename (optional). If provided, also exports to CSV")
    parser.add_argument("--csv-only", action="store_true", help="Export to CSV only, skip BigQuery insert")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    parser.add_argument("--insert_each_day", action="store_true", help="Loop day by day between start-date and end-date (Vietnam time) and call the API per day")
    
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
        # Default: Yesterday
        yesterday = datetime.now() - timedelta(days=1)
        start_date_arg = yesterday.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday.strftime("%Y-%m-%dT23:59:59")
    
    if args.insert_each_day:
        if args.All:
            raise ValueError("--insert_each_day cannot be combined with --All")
        if not start_date_arg or not end_date_arg:
            raise ValueError("--insert_each_day requires both --start-date and --end-date")

        daily_ranges = build_daily_ranges(start_date_arg, end_date_arg)
        entries_raw = []
        total_days = len(daily_ranges)
        for idx, (day_start_ts, day_end_ts) in enumerate(daily_ranges, 1):
            print(f"\nDay {idx}/{total_days}: {ts_to_vn_string(day_start_ts)} -> {ts_to_vn_string(day_end_ts)}")
            day_entries = load_data(start_date=day_start_ts, end_date=day_end_ts, label=f"day {idx}")
            entries_raw.extend(day_entries)
        print(f"\n✓ Aggregated {len(entries_raw)} entries across {total_days} day(s)\n")
    else:
        entries_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
   # Check if there are any orders
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
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
        output_file = output_dir / f"pancake_raw_stats_inventory_variations_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")

if __name__ == "__main__":
    main()

# Placeholder for next edit
