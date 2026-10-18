#!/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/lsoul_document/.venv/bin/python3
import argparse
import warnings
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

            # Core identity & audit
            "id": "entry_id",
            "inserted_at": "inserted_at",
            "updated_at": "updated_at",
            "customer_id": "customer_id",
            "username": "username",
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
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        return int(dt.timestamp())
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")

def load_data(start_date=None, end_date=None):
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
                params['start_time_inserted_at'] = start_datetime
            if end_datetime:
                params['end_time_inserted_at'] = end_datetime

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
        print(f"  Entries with orders from API: {len(entries_raw)}")
        print(f"  Order items (rows): {len(df)}")
        print(f"  Note: Each order item creates a separate row in the table")
        print(f"  Item-level columns: {len([c for c in df.columns if c.startswith('shop_customer_addresses.')])}")
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
        output_file = output_dir / f"pancake_raw_customers_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")

if __name__ == "__main__":
    main()

# Placeholder for next edit
