#!/usr/bin/env python3
"""
Script to load product variation data from Pancake API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's product variations from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)

Usage:
    python3 versions/CSV_V2_manual_data_export_product_variation.py              # Get yesterday's product variations from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)
    python3 versions/CSV_V2_manual_data_export_product_variation.py --start_date 2024-01-01T00:00:00 --end_date 2026-05-24T23:59:59
    python3 versions/CSV_V2_manual_data_export_product_variation.py --All           # Get all product variations with no date filter (use with caution)
"""
import argparse
import warnings
import requests
import pytz
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OUTPUT_PATH = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv")

COLUMN_RENAME_MAP = {

   #Variation-level fields (from API response):
    "updated_at": "updated_at",
    "inserted_at": "inserted_at",
    "id": "variation_id",
    "display_id": "variation_display_id",
    "size_name": "size_name",
    "size_value": "size_value",
    "color_name": "color_name",
    "color_value": "color_value",
    # --- Pricing & Costs ---
    "retail_price": "retail_price",
    "retail_price_after_discount": "retail_price_after_discount",
    "average_imported_price": "average_imported_price",
    "last_imported_price": "last_imported_price",
    "total_purchase_price": "total_purchase_price",
    "price_at_counter": "price_at_counter",
    "wholesale_price": "variation_wholesale_price",
    # --- Stock & Status ---
    "remain_quantity": "remain_quantity",
    "is_hidden": "is_hidden",
    "is_locked": "is_locked",
    "is_removed": "is_removed",
    "is_sell_negative_variation": "is_sell_negative",
    "is_composite": "is_composite",
    #"barcode": "variation_barcode",
    #"price_table": "variation_price_table",
    #"weight": "product_weight",
    #"images": "images",
    #"videos": "variation_videos",
    #"composite_products": "composite_components",
    #"bonus_variations": "bonus_variations",
    
    #Product-level fields (from 'product' nested object):
    "product.inserted_at": "product_inserted_at",
    "product_id": "product_id",
    "product.display_id": "product_display_id",
    "product.name": "product_name",
    "product.product_attributes": "product_attributes",
    "product.note": "product_internal_note",
    "product.note_product": "product_public_note",
    "product.supplier_product_ids": "product_supplier_product_ids",
    "product.tags": "product_tags",
    #"product.measure_group_id": "product_measure_group_id",
    #"product.is_published": "product_is_published",
    #"product.image": "product_image",
    #"product.categories": "product_categories",

    #Variation-warehouse level fields (from 'variations_warehouses' nested object):
    "variations_warehouses.warehouse_id":"variations_warehouses_warehouse_id",
    "variations_warehouses.actual_remain_quantity":"variations_warehouses_actual_remain_quantity",
    "variations_warehouses.pending_quantity":"variations_warehouses_pending_quantity",
    "variations_warehouses.remain_quantity":"variations_warehouses_remain_quantity",
    "variations_warehouses.total_quantity":"variations_warehouses_total_quantity",
    "variations_warehouses.returning_quantity":"variations_warehouses_returning_quantity",
    "variations_warehouses.waiting_quantity":"variations_warehouses_waiting_quantity"
    #"variations_warehouses.selling_avg":"variations_warehouses_selling_avg",
     #"product.manipulation_warehouses": "product_manipulation_warehouses"
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
    # Note: Input dates are treated as Vietnam time (UTC+7) and converted to Unix timestamp for API
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
                'page_size': page_size,
            }
            # Only add date parameters if they were provided
            if start_datetime:
                params['start_time_update'] = start_datetime
            if end_datetime:
                params['end_time_update'] = end_datetime
            
            response = requests.get(api_url, params=params, timeout=69)
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
    
    print(f"Successfully fetched {len(all_products)} variations from API\n")
    return all_products


def flatten_data(products_raw):
    has_items = any(isinstance(o.get("product"), list) and o.get("product") for o in products_raw)
    
    if has_items:
        df = json_normalize(
            products_raw,
            record_path="product",
            meta=[col for col in products_raw[0].keys() if col != "product"],
            record_prefix="product_",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        print(f"\nData Structure:")
        print(f"  Products from API: {len(products_raw)}")
        print(f"  Product variations (rows): {len(df)}")
        print(f"  Note: Each product variation creates a separate row in the table")
        print(f"  Product details-level columns: {len([c for c in df.columns if c.startswith('variations_')])}")
        print(f"  Product-level columns: {len([c for c in df.columns if not c.startswith('variations_')])}")
    else:
        df = json_normalize(products_raw, sep=".", errors="ignore")
        print(f"\nData Structure:")
        print(f"  Products from API: {len(products_raw)}")
        print(f"  Rows to insert: {len(df)}")
    return df.copy()

def pivot_fields_column(df):
    """Pivot the 'fields' list column into size_name, size_value, color_name, color_value columns."""
    if 'fields' not in df.columns:
        return df

    size_names, size_values, color_names, color_values = [], [], [], []

    for fields in df['fields']:
        size_name = size_value = color_name = color_value = ''
        if isinstance(fields, list):
            for field in fields:
                if isinstance(field, dict):
                    name = str(field.get('name', ''))
                    value = field.get('value', '')
                    if 'size' in name.lower():
                        size_name = name
                        size_value = value
                    elif 'màu' in name.lower() or 'mau' in name.lower():
                        color_name = name
                        color_value = value
        size_names.append(size_name)
        size_values.append(size_value)
        color_names.append(color_name)
        color_values.append(color_value)

    df['size_name'] = size_names
    df['size_value'] = size_values
    df['color_name'] = color_names
    df['color_value'] = color_values
    return df


def expand_warehouses(df):
    """Explode variations_warehouses list into one row per warehouse."""
    if 'variations_warehouses' not in df.columns:
        return df

    df = df.explode('variations_warehouses').reset_index(drop=True)

    wh_expanded = pd.json_normalize(
        df['variations_warehouses'].apply(lambda x: x if isinstance(x, dict) else {})
    ).add_prefix('variations_warehouses.')

    df = df.drop(columns=['variations_warehouses']).reset_index(drop=True)
    df = pd.concat([df, wh_expanded], axis=1)
    return df


def rename_and_reorder_columns(df):
    # Keep all columns from the dataframe (don't filter by COLUMN_RENAME_MAP)
    # Just rename the ones that exist in the mapping
    new_df_dict = {}
    
    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
    
    return pd.DataFrame(new_df_dict)


def flatten_tags(df):
    """Extract 'note' values from product_tags list of dicts into a comma-separated string."""
    if 'product_tags' not in df.columns:
        return df
    def extract_notes(tags):
        if isinstance(tags, list):
            return ', '.join(str(t['note']) for t in tags if isinstance(t, dict) and t.get('note'))
        return ''
    df['product_tags'] = df['product_tags'].apply(extract_notes)
    return df


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
        'inserted_at','updated_at','product_inserted_at'
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


def normalize_id_strings(df):
    """Normalize ID-like columns to remove float-ish suffixes (e.g., 123456.0 → 123456)."""
    id_like_cols = [
        "is_hidden",
        "is_locked",
        "is_removed",
        "is_composite",
        "is_sell_negative_variation",
        "remain_quantity",
        "variations_warehouses_actual_remain_quantity",
        "variations_warehouses_pending_quantity",
        "variations_warehouses_remain_quantity",
        "variations_warehouses_returning_quantity",
        "variations_warehouses_total_quantity",
        "variations_warehouses_waiting_quantity"
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

def clean_empty_json(df):
    # Replace NaN with empty string and remove empty JSON objects
    # Only process object/string columns to preserve numeric types
    for col in df.columns:
        if df[col].dtype == 'object':
            df[col] = df[col].astype(str).replace(['nan', '{}','[]','None','null'], '')
    return df

def export_csv(df, output_file):
    """Export DataFrame to CSV with UTF-8 BOM encoding."""
    df.astype('object').to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS product data to CSV")
    parser.add_argument("--All", action="store_true", default=False, help="Fetch all data without date filters")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    parser.add_argument("--yesterday", action="store_true", help="Fetch data from yesterday only (default behavior)")
    parser.add_argument("--output", help="Output CSV filename (auto-generated if not specified)")
    args = parser.parse_args()
    
       # Determine date range based on options:
    # 1. Manual dates: Use provided --start-date and --end-date
    # 2. --All flag: No date filters
    # 3. Default: Yesterday 00:00:00 to 23:59:59
    if args.start_date or args.end_date:
        start_date_arg = args.start_date
        end_date_arg = args.end_date
    elif args.All:
        # Fetch all data (no date filters)
        start_date_arg = None
        end_date_arg = None
    else:
        # Default: Yesterday in Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")

    products_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
    if not products_raw or len(products_raw) == 0:
        print("0 entries found. No data to export.")
        return
    
    df = flatten_data(products_raw)
    df = pivot_fields_column(df)
    df = expand_warehouses(df)
    df = rename_and_reorder_columns(df)
    df = flatten_tags(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = normalize_id_strings(df)
    df = clean_empty_json(df)

    OUTPUT_PATH.mkdir(parents=True, exist_ok=True)
    output_file = OUTPUT_PATH / (args.output or f"pancake_raw_product_variations_{datetime.now().strftime('%Y%m%d%H%M%S')}.csv")
    
    export_csv(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()
