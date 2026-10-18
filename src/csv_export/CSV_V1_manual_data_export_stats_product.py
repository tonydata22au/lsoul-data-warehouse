# %%
#!/usr/bin/env python3
import json
import argparse
import warnings
import requests
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
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
    # Maps from flatten_data() output columns to desired final names
    #  
                "id": "stats_id",
                "inserted_at": "inserted_at",
                "begin_inventory": "begin_inventory",
                "begin_inventory_value": "begin_inventory_value",
                "end_inventory": "end_inventory",
                "end_inventory_value": "end_inventory_value",
                "product_id": "product_id",
                "product.name": "product_name",
                "product.inserted_at": "product_inserted_at",
                "product.category_ids": "product_category_ids",
                "product.custom_id": "product_custom_id",
                "product.display_id": "product_display_id",
                "purchase_import": "purchase_import",
                "return_import": "return_import",
                "stocktaking_import": "stocktaking_import",
                "transfer_import": "transfer_import",
                "total_import": "total_import",
                "total_import_value": "total_import_value",
                "purchase_export": "purchase_export",
                "transfer_export": "transfer_export",
                "sell_export": "sell_export",
                "stocktaking_export": "stocktaking_export",
                "total_export": "total_export",
                "total_export_value": "total_export_value"
}

def parse_date_to_unix(date_string):
    """
    Convert Vietnam local time string (YYYY-MM-DDTHH:MM:SS) to UTC Unix timestamp.
    Accepts int/float and returns it unchanged.
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
    Load data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/inventory_analytics/inventory_by_product"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_stats_products = []
    page = 1
    page_size = 1000
    type_param = 'actual'
    
    # Prepare default timestamps: 1 year ago (VN time) -> now
    now_vn = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
    default_start_ts = int((now_vn - timedelta(days=365)).astimezone(timezone.utc).timestamp())
    default_end_ts = int(now_vn.astimezone(timezone.utc).timestamp())

    # Use provided date strings when given; otherwise use defaults (Unix timestamps)
    startDate = parse_date_to_unix(start_date) if start_date else default_start_ts
    endDate = parse_date_to_unix(end_date) if end_date else default_end_ts
    
    print(f"Fetching data from API{f' ({label})' if label else ''}...")
    print(f"  Start date: {ts_to_vn_string(startDate)} (UTC ts: {startDate})")
    print(f"  End date: {ts_to_vn_string(endDate)} (UTC ts: {endDate})")
    
    while True:
        try:
            params = {
                "api_key": api_key,
                "page": page,
                "page_size": page_size,
                "type": type_param,
                "startDate": startDate,
                "endDate": endDate
            }
            
            response = requests.get(api_url, params=params, timeout=9999)
            response.raise_for_status()
            payload = response.json()
            
            stats_products = payload.get("data", [])
            if not stats_products:
                break
            
            all_stats_products.extend(stats_products)
            total_pages = payload.get("total_pages", 1)
            print(f"  Fetched page {page}/{total_pages}: {len(stats_products)} entries (total: {len(all_stats_products)})")
            
            # Check if there are more pages
            if len(stats_products) < page_size and page >= total_pages:
                break
            
            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"Successfully fetched {len(all_stats_products)} products from API\n")
    return all_stats_products


def flatten_data(stats_products_raw):
    has_items = any(isinstance(o.get("product"), list) and o.get("product") for o in stats_products_raw)
    
    if has_items:
        df = json_normalize(
            stats_products_raw,
            record_path="product",
            record_prefix="product_",
            sep=".",
            errors="ignore"
        )
    else:
        df = json_normalize(stats_products_raw, sep=".", errors="ignore")
    
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


def convert_dates_to_timestamp(df):
    date_columns = [
        'product_inserted_at'
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
    for col in df.columns:
        df[col] = df[col].astype(str).replace(['nan', '{}','[]'], '')
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
    # BOM helps Excel properly detect UTF-8 encoding for Vietnamese characters
    df.to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS statistics by product data to CSV")
    parser.add_argument("--list", action="store_true", help="List all available columns")
    parser.add_argument("--output", default=None, help="Output filename (optional). If omitted, a timestamped filename will be used")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00). If omitted, default start date filter is used (1 year ago).")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59). If omitted, default end date filter is used (today).")
    parser.add_argument("--yesterday", action="store_true", help="Fetch data from yesterday (00:00:00 to 23:59:59). Overrides --start-date and --end-date.")
    parser.add_argument("--All", action="store_true", help="Fetch all data from 2019-01-01 to now. Overrides --start-date, --end-date, and --yesterday.")
    parser.add_argument("--insert_each_day", action="store_true", help="Loop day by day between start-date and end-date (Vietnam time) and call the API per day")
    
    args = parser.parse_args()
    
    # Default to yesterday (VN time) unless overridden by flags or explicit dates
    yesterday_vn = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")) - timedelta(days=1)
    default_start = yesterday_vn.strftime("%Y-%m-%dT00:00:00")
    default_end = yesterday_vn.strftime("%Y-%m-%dT23:59:59")

    start_date_arg = args.start_date or default_start
    end_date_arg = args.end_date or default_end

    if args.All:
        start_date_arg = "2019-01-01T00:00:00"
        end_date_arg = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%Y-%m-%dT23:59:59")
    elif args.yesterday:
        start_date_arg = default_start
        end_date_arg = default_end
    
    if args.insert_each_day:
        if args.All:
            raise ValueError("--insert_each_day cannot be combined with --All")
        if not start_date_arg or not end_date_arg:
            raise ValueError("--insert_each_day requires both --start-date and --end-date")

        daily_ranges = build_daily_ranges(start_date_arg, end_date_arg)
        stat_products_raw = []
        total_days = len(daily_ranges)
        for idx, (day_start_ts, day_end_ts) in enumerate(daily_ranges, 1):
            print(f"\nDay {idx}/{total_days}: {ts_to_vn_string(day_start_ts)} -> {ts_to_vn_string(day_end_ts)}")
            day_entries = load_data(start_date=day_start_ts, end_date=day_end_ts, label=f"day {idx}")
            day_label = datetime.fromtimestamp(day_start_ts, tz=timezone.utc).astimezone(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%Y-%m-%dT00:00:00")
            for entry in day_entries:
                entry["inserted_at"] = day_label
            stat_products_raw.extend(day_entries)
        print(f"\n✓ Aggregated {len(stat_products_raw)} entries across {total_days} day(s)\n")
    else:
        stat_products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any products
    if not stat_products_raw or len(stat_products_raw) == 0:
        print("0 entry found. No data to export.")
        return

    df = flatten_data(stat_products_raw)
    
    if args.list:
        list_columns(df)
        return
    
    
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)

    # Filter out rows with non-positive inventory metrics (all four must be > 0)
    for col in ["begin_inventory", "begin_inventory_value", "end_inventory", "end_inventory_value"]:
        if col not in df.columns:
            df[col] = 0
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)
    df = df[
        (df["begin_inventory"] > 0)
        & (df["begin_inventory_value"] > 0)
        & (df["end_inventory"] > 0)
        & (df["end_inventory_value"] > 0)
    ].copy()

    # Determine output filename if not provided
    output_dir = OutputPath
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if args.output:
        output_file = output_dir / args.output
    else:
        now_ts = datetime.now().strftime('%Y%m%d%H%M%S')
        output_file = output_dir / f"pancake_raw_stats_product_{now_ts}.csv"

    export_data(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()

# Placeholder for next edit