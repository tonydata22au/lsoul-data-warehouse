#!/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/lsoul_document/.venv/bin/python3
import argparse
import warnings
import requests
from datetime import datetime, timedelta, timezone
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import urllib3
import pytz
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars


# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OUTPUT_PATH = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv")


COLUMN_RENAME_MAP = {
    # Maps from flatten_data() output columns to desired final names
    # Base variation fields
    "inserted_at": "inserted_at",
    "id": "variation_id",
    "display_id": "display_id",
    "fields": "fields", 
    "is_hidden": "is_hidden",
    "is_locked": "is_locked",
    "is_sell_negative_variation": "is_sell_negative_variation",
    "average_imported_price": "average_imported_price",
    "last_imported_price": "last_imported_price",
    "price_at_counter": "price_at_counter",
    "product_id": "product_id",
    "remain_quantity": "remain_quantity",
    "retail_price": "retail_price",
    "total_purchase_price": "total_purchase_price",
    "images": "images",
    # Product nested fields (from product object)
    "variation.product.display_id": "variation_product_display_id",
    "variation.product.inserted_at": "variation_product_inserted_at",
    "variation.product.name": "variation_product_name",
    "variation.product.product_attributes": "variation_product_attributes",
    "variation.product.supplier_product_ids": "variation_product_supplier_product_ids",
    # Warehouse nested fields (from variations_warehouses array)
    "variation.variations_warehouses.actual_remain_quantity": "variations_warehouses_actual_remain_quantity",
    "variation.variations_warehouses.pending_quantity": "variations_warehouses_pending_quantity",
    "variation.variations_warehouses.remain_quantity": "variations_warehouses_remain_quantity",
    "variation.variations_warehouses.returning_quantity": "variations_warehouses_returning_quantity",
    "variation.variations_warehouses.selling_avg": "variations_warehouses_selling_avg",
    "variation.variations_warehouses.total_quantity": "variations_warehouses_total_quantity",
    "variation.variations_warehouses.waiting_quantity": "variations_warehouses_waiting_quantity",
    "variation.variations_warehouses.warehouse_id": "variations_warehouses_warehouse_id"           
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

def load_data(start_date=None, end_date=None):
    """
    Load product data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/products/variations"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_products = []
    page = 1
    page_size = 1000
    
    # Convert date strings to Unix timestamps
    start_datetime = parse_date_to_unix(start_date)
    end_datetime = parse_date_to_unix(end_date)
    
    print(f"Fetching data from API...")
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
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['startDate'] = start_datetime
            if end_datetime:
                params['endDate'] = end_datetime
            
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
        'inserted_at','variation_product_inserted_at'
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
        # Default: Yesterday in Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")
    
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

     # Determine output filename if not provided
    output_dir = OUTPUT_PATH
    output_dir.mkdir(parents=True, exist_ok=True)

    # Determine output filename if not provided
    if args.output:
        output_file = output_dir / args.output
    else:
        now_ts = datetime.now().strftime('%Y%m%d%H%M%S')
        output_file = output_dir / f"pancake_raw_variations_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")

if __name__ == "__main__":
    main()


# Placeholder for next edit
