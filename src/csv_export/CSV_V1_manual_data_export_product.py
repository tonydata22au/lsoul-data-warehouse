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
                    'returning_quantity', 'selling_avg', 'shelf_position', 'waiting_quantity']

COLUMN_RENAME_MAP = {
    # Product-level columns
    "inserted_at": "inserted_at",
    "id": "product_id",
    "name": "product_name",
    "custom_id": "custom_id",
    "display_id": "display_id",
    "image": "image",
    "wholesale_price": "wholesale_price",
    "product_attributes": "product_attributes",
    "supplier_product_ids": "supplier_product_ids",
    "type": "type",
    # Variation-level columns
    "variations.average_imported_price": "variation_average_imported_price",
    "variations.display_id": "variation_display_id",
    "variations.inserted_at": "variation_inserted_at",
    "variations.is_hidden": "variation_is_hidden",
    "variations.is_locked": "variation_is_locked",
    "variations.is_removed": "variation_is_removed",
    "variations.is_sell_negative_variation": "variation_is_sell_negative",
    "variations.last_imported_price": "variation_last_imported_price",
    "variations.price_at_counter": "variation_price_at_counter",
    "variations.remain_quantity": "variation_remain_quantity",
    "variations.retail_price": "variation_retail_price",
    "variations.retail_price_after_discount": "variation_retail_price_after_discount",
    "variations.total_purchase_price": "variation_total_purchase_price",
    # Warehouse-level columns
    "variations.variation_warehouses.actual_remain_quantity": "variation_warehouse_actual_remain_quantity",
    "variations.variation_warehouses.total_quantity": "variation_warehouse_total_quantity",
    "variations.variation_warehouses.warehouse_id": "variation_warehouse_id",
    "variations.variation_warehouses.returning_quantity": "variation_warehouse_returning_quantity",    
    "variations.variation_warehouses.waiting_quantity": "variation_warehouse_waiting_quantity",
    
                #"categories": [],      
                 #"is_sell_negative": "is_sell_negative",          
                 #"is_published": null,
                 #"is_published": null,
                 #"manipulation_warehouses": [],
                #"measure_group_id": null,
                #"note": null,
                #"note_product": "",
                    #"variations.is_composite": "variation_is_composite",
                    #"barcode": "Z26010017-4",
                    #"bonus_variations": [],
                    #"composite_products": [],
                    # "batch_position": null,
                    # "pending_quantity": 0,  
                    #"variations.variation_warehouses.selling_avg": "variation_warehouse_selling_avg",
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
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/products"
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
    has_variations = any(isinstance(p.get("variations"), list) and p["variations"] for p in products_raw)
    
    if not has_variations:
        df = json_normalize(products_raw, sep=".", errors="ignore")
        print(f"\nData Structure: {len(products_raw)} products → {len(df)} rows")
        return df
    
    # Flatten variations into rows
    meta_cols = [col for col in products_raw[0].keys() if col != "variations"]
    df = json_normalize(products_raw, record_path="variations", meta=meta_cols,
                        record_prefix="variations.", sep=".", errors="ignore")
    
    print(f"\nData Structure:")
    print(f"  Products: {len(products_raw)} → Variations: {len(df)}")
    
    # Find warehouse column (handles both naming conventions)
    warehouse_col = next((c for c in df.columns if 'warehouses' in c.lower() and 'variations' in c.lower()), None)
    if not warehouse_col:
        return df
    
    # Explode warehouses: vectorized approach
    df[warehouse_col] = df[warehouse_col].apply(lambda x: x if isinstance(x, list) and x else [{}])
    df = df.explode(warehouse_col, ignore_index=True)
    
    # Extract warehouse fields using vectorized operations
    warehouse_data = df[warehouse_col].apply(lambda x: x if isinstance(x, dict) else {})
    for field in WAREHOUSE_FIELDS:
        df[f'variations.variation_warehouses.{field}'] = warehouse_data.apply(lambda x: x.get(field))
    
    print(f"  After warehouse explode: {len(df)} rows")
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
    for col in ['inserted_at', 'variation_inserted_at']:
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
    output_file = OUTPUT_PATH / (args.output or f"pancake_raw_product_list_{datetime.now().strftime('%Y%m%d%H%M%S')}.csv")
    
    export_csv(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()
