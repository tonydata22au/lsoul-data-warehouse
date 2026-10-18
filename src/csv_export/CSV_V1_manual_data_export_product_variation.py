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

OUTPUT_PATH = Path("/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv")

WAREHOUSE_FIELDS = ['actual_remain_quantity', 'total_quantity', 'warehouse_id', 
                    'returning_quantity', 'selling_avg', 'shelf_position', 'waiting_quantity',
                    'pending_quantity', 'remain_quantity']

COLUMN_RENAME_MAP = {
    # Maps from flatten_data() output columns to desired final names
    
    # --- Variation Identifiers ---
     # --- Timestamps ---
    "inserted_at": "inserted_at",
    "id": "variation_id",
    "product_id": "product_id",
    "display_id": "display_id",
    "barcode": "variation_barcode",
    
    # --- Pricing & Costs ---
    "retail_price": "retail_price",
    "retail_price_after_discount": "retail_price_after_discount",
    "average_imported_price": "average_imported_price",
    "last_imported_price": "last_imported_price",
    "total_purchase_price": "total_purchase_price",
    #"price_at_counter": "variation_price_at_counter",
    #"wholesale_price": "variation_wholesale_price",
    #"price_table": "variation_price_table",
    
    # --- Stock & Status ---
    "remain_quantity": "remain_quantity",
    #"weight": "product_weight",
    "is_hidden": "is_hidden",
    "is_locked": "is_locked",
    "is_removed": "is_removed",
    #"is_composite": "is_composite",
    #"is_sell_negative_variation": "is_sell_negative",
    
   
    
    # --- Nested/Complex Fields ---
    "images": "images",
    #"videos": "variation_videos",
    "fields": "fields",
    #"composite_products": "composite_components",
    #"bonus_variations": "bonus_variations",
    
    # --- Parent Product Info (from 'product' nested object) ---
    "product.name": "product_name",
    "product.display_id": "product_display_id",
    "product.inserted_at": "product_inserted_at",
    #"product.is_published": "product_is_published",
    "product.image": "product_image",
    #"product.categories": "product_categories",
    #"product.tags": "product_tags",
    "product.product_attributes": "product_attributes",
    #"product.measure_group_id": "product_measure_group_id",
    #"product.note": "product_note",
    #"product.note_product": "product_note_product",
    "product.supplier_product_ids": "product_supplier_product_ids",
    #"product.manipulation_warehouses": "product_manipulation_warehouses"
    "variations_warehouses.actual_remain_quantity":"variations_warehouses_actual_remain_quantity",
    "variations_warehouses.pending_quantity":"variations_warehouses_pending_quantity",
    "variations_warehouses.remain_quantity":"variations_warehouses_remain_quantity",
    "variations_warehouses.returning_quantity":"variations_warehouses_returning_quantity",
    "variations_warehouses.selling_avg":"variations_warehouses_selling_avg",
    "variations_warehouses.total_quantity":"variations_warehouses_total_quantity",
    "variations_warehouses.waiting_quantity":"variations_warehouses_waiting_quantity",
    "variations_warehouses.warehouse_id":"variations_warehouses_warehouse_id",
}

def parse_date_to_unix(date_string):
    """Convert date string 'YYYY-MM-DDTHH:MM:SS' to Unix timestamp."""
    if not date_string or not date_string.strip():
        return None
    try:
        return int(datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S").timestamp())
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected: YYYY-MM-DDTHH:MM:SS")


def load_data(start_date=None, end_date=None):
    """Load product data from Pancake API with optional date filters."""
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/products/variations"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_products = []
    page = 1
    page_size = 1000
    
    start_ts = parse_date_to_unix(start_date)
    end_ts = parse_date_to_unix(end_date)
    
    print("Fetching data from API...")
    if start_ts:
        print(f"  Start date: {datetime.fromtimestamp(start_ts).strftime('%Y-%m-%d %H:%M:%S')}")
    if end_ts:
        print(f"  End date: {datetime.fromtimestamp(end_ts).strftime('%Y-%m-%d %H:%M:%S')}")
    if not start_ts and not end_ts:
        print("  No date filters applied - fetching all data")
    
    while True:
        params = {'api_key': api_key, 'page': page, 'page_size': page_size}
        if start_ts:
            params['startDate'] = start_ts
        if end_ts:
            params['endDate'] = end_ts
        
        try:
            response = requests.get(api_url, params=params, timeout=9999)
            response.raise_for_status()
            payload = response.json()
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        
        products = payload.get("data", [])
        if not products:
            break
        
        all_products.extend(products)
        total_pages = payload.get("total_pages", 1)
        print(f"  Fetched page {page}/{total_pages}: {len(products)} entries (total: {len(all_products)})")
        
        if page >= total_pages:
            break
        page += 1
    
    print(f"Successfully fetched {len(all_products)} products from API\n")
    return all_products


def flatten_data(products_raw):
    """Flatten nested product data and explode warehouse arrays into separate rows."""
    # First, normalize the base product data
    df = json_normalize(products_raw, sep=".", errors="ignore")
    print(f"\nData Structure: {len(products_raw)} products → {len(df)} rows")
    
    # Check if variations_warehouses exists and is a list
    warehouse_col = next((c for c in df.columns if 'variations_warehouses' in c.lower()), None)
    if not warehouse_col:
        print("  No variations_warehouses column found")
        return df
    
    print(f"  Found warehouse column: {warehouse_col}")
    
    # Ensure variations_warehouses is a list (handle empty/null cases)
    df[warehouse_col] = df[warehouse_col].apply(lambda x: x if isinstance(x, list) and x else [{}])
    
    # Explode warehouses into separate rows
    df = df.explode(warehouse_col, ignore_index=True)
    
    # Extract warehouse fields from the exploded dictionaries
    warehouse_data = df[warehouse_col].apply(lambda x: x if isinstance(x, dict) else {})
    for field in WAREHOUSE_FIELDS:
        df[f'variations_warehouses.{field}'] = warehouse_data.apply(lambda x: x.get(field))
    
    # Drop the original nested column to avoid confusion
    df = df.drop(columns=[warehouse_col], errors='ignore')
    
    print(f"  After warehouse explode: {len(df)} rows")
    print(f"  Extracted warehouse fields: {[f'variations_warehouses.{f}' for f in WAREHOUSE_FIELDS]}")
    return df


def rename_columns(df):
    """Rename and select columns based on COLUMN_RENAME_MAP."""
    return pd.DataFrame({new: df[old] for old, new in COLUMN_RENAME_MAP.items() if old in df.columns})


def convert_booleans(df):
    """Convert boolean True/False values to 1/0."""
    bool_map = {True: 1, 'True': 1, False: 0, 'False': 0}
    for col in df.columns:
        if df[col].astype(str).isin(['True', 'False']).any():
            df[col] = df[col].map(lambda x: bool_map.get(x, x))
    return df


def convert_dates(df):
    """Convert datetime columns to timestamp format."""
    for col in ['inserted_at', 'product_inserted_at']:
        if col in df.columns:
            try:
                df[col] = pd.to_datetime(df[col]).dt.strftime('%Y%m%d%H%M%S')
            except:
                pass
    return df


def clean_data(df):
    """Clean empty JSON objects and NaN values in object columns."""
    for col in df.select_dtypes(include='object').columns:
        df[col] = df[col].astype(str).replace(['nan', '{}', '[]', 'None'], '')
    return df


def list_columns(df):
    """Print available columns with their renamed versions."""
    print("\nAvailable columns:")
    for i, col in enumerate(df.columns, 1):
        new_name = COLUMN_RENAME_MAP.get(col, col)
        print(f"  {i:3d}. {col} → {new_name}")
    print(f"\nTotal: {len(df.columns)} columns\n")


def export_csv(df, output_file):
    """Export DataFrame to CSV with UTF-8 BOM encoding."""
    df.astype('object').to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS product data to CSV")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.add_argument("--start-date", help="Start date: YYYY-MM-DDTHH:MM:SS")
    parser.add_argument("--end-date", help="End date: YYYY-MM-DDTHH:MM:SS")
    parser.add_argument("--list", action="store_true", help="List available columns and exit")
    parser.add_argument("--output", help="Output CSV filename (auto-generated if not specified)")
    args = parser.parse_args()
    
    # Determine date range
    if args.All:
        start_date, end_date = None, None
    elif args.start_date or args.end_date:
        start_date, end_date = args.start_date, args.end_date
    else:
        yesterday = datetime.now() - timedelta(days=1)
        start_date = yesterday.strftime("%Y-%m-%dT00:00:00")
        end_date = yesterday.strftime("%Y-%m-%dT23:59:59")

    products_raw = load_data(start_date, end_date)
    
    if not products_raw or len(products_raw) == 0:
        print("0 entries found. No data to export.")
        return
    
    df = flatten_data(products_raw)
    
    if args.list:
        list_columns(df)
        return
    
    df = rename_columns(df)
    df = convert_booleans(df)
    df = convert_dates(df)
    df = clean_data(df)

    OUTPUT_PATH.mkdir(parents=True, exist_ok=True)
    output_file = OUTPUT_PATH / (args.output or f"pancake_raw_product_variations_{datetime.now().strftime('%Y%m%d%H%M%S')}.csv")
    
    export_csv(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()
