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

def load_data(start_date=None, end_date=None):
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

    ecom_products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any products
    if not ecom_products_raw or len(ecom_products_raw) == 0:
        print("0 entry found. No data to export.")
        return

    df = flatten_data(ecom_products_raw)
    
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
        output_file = output_dir / f"pancake_raw_ecom_product_list_{now_ts}.csv"

    export_data(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()