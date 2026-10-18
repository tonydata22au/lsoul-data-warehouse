#!/usr/bin/env python3
"""
Script to load order data from Jushuitan API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's orders from T00:00:00 to T23:59:59 in shanghai time

Usage:
    python3 versions/CSV_V1_manual_data_export_purchase.py               # Get yesterday's purchases from T00:00:00 to T23:59:59
    python3 versions/CSV_V1_manual_data_export_purchase.py --start_date 2026-07-13T00:00:00 --end_date 2026-07-13T23:59:59
    python3 versions/CSV_V1_manual_data_export_purchase.py --ALL           # Get all purchases with no date filter (use with caution)
    cd "g:\My Drive\03. CODE & DOCUMENTS\lsoul_document"; python versions/CSV_V1_manual_data_export_purchase.py --start-date 2026-07-13T00:00:00 --end-date 2026-07-13T23:59:59
"""
import json
import argparse
import warnings
import requests
from datetime import datetime, timedelta, timezone
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OUTPUT_DIR = Path(
    "g:/My Drive/03. CODE & DOCUMENTS/lsoul_document/data_export_csv"
)
    

COLUMN_RENAME_MAP = {
    # Maps from flatten_data() output columns to desired final names
    # Note: Output column names use underscores instead of dots for BigQuery compatibility
            "inserted_at": "inserted_at",
            "id": "purchase_id",
            "display_id": "display_id",
            "note": "note",
            "is_lock": "is_lock",
            "total_quantity": "total_quantity",
            "status": "status",
            "total_price": "total_price",
            "updated_at": "updated_at",
            "warehouse.id": "warehouse_id",
            "warehouse.name": "warehouse_name",
            "not_create_transaction": "not_create_transaction",
            "user_id": "user_id",
            #user (JSON NORMALIZED)
            "user.name": "user_name",
            
            "total_remain_quantity": "total_remain_quantity",
            "supplier_products_id": "supplier_products_id",
            "created_type": "created_type",
            "type_of_transaction": "type_of_transaction",
            "is_transfer": "is_transfer",
            "discount": "discount",
            "total_remain_price": "total_remain_price",
        
            #items (JSON NORMALIZED)
            "items.id": "items_id",
            "items.display_id": "items_display_id",
            "items.product_name": "items_product_name",
            "items.inserted_at": "items_inserted_at",
            "items.estimated_quantity": "items_estimated_quantity",
            "items.quantity": "items_quantity",
            "items.gross_price": "items_gross_price",
            "items.discount": "items_discount",
            "items.remain_quantity": "items_remain_quantity",
            "items.selling_status": "items_selling_status",
            "items.tax_rate": "items_tax_rate",
            "items.variation_id": "items_variation_id",
            

            #"items.variation" (JSON NORMALIZED)
            "items.variation.display_id": "items_variation_display_id",
            "items.variation.fields": "items_variation_fields",
            "items.variation.images": "items_variation_images",
            "items.variation.inserted_at": "items_variation_inserted_at",
            "items.variation.is_hidden": "items_variation_is_hidden",
            "items.variation.is_locked": "items_variation_is_locked",
            "items.variation.is_removed": "items_variation_is_removed",
            "items.variation.is_sell_negative_variation": "items_variation_is_sell_negative_variation",
            "items.variation.last_imported_price": "items_variation_last_imported_price",
            "items.variation.price_at_counter": "items_variation_price_at_counter",
            "items.variation.remain_quantity": "items_variation_remain_quantity",
            "items.variation.retail_price": "items_variation_retail_price",
            "items.variation.retail_price_after_discount": "items_variation_retail_price_after_discount",
            "items.variation.product_id": "items_variation_product_id",

            #"items.variation.product" (JSON NORMALIZED - use flattened fields below)
            "items.variation.product.display_id": "items_variation_product_display_id",
            "items.variation.product.name": "items_variation_product_name",
            "items.variation.product.image": "items_variation_product_image",
            "items.variation.product.inserted_at": "items_variation_product_inserted_at",
            "items.variation.product.product_attributes": "items_variation_product_product_attributes",
            "items.variation.product.supplier_product_ids": "items_variation_product_supplier_product_ids",
            "items.variation.variations_warehouses.warehouse_id": "items_variation_variations_warehouses_warehouse_id",
            "items.variation.variations_warehouses.actual_remain_quantity": "items_variation_variations_warehouses_actual_remain_quantity",
            "items.variation.variations_warehouses.pending_quantity": "items_variation_variations_warehouses_pending_quantity",
            "items.variation.variations_warehouses.remain_quantity": "items_variation_variations_warehouses_remain_quantity",
            "items.variation.variations_warehouses.returning_quantity": "items_variation_variations_warehouses_returning_quantity",
            "items.variation.variations_warehouses.selling_avg": "items_variation_variations_warehouses_selling_avg",
            "items.variation.variations_warehouses.total_quantity": "items_variation_variations_warehouses_total_quantity",
            "items.variation.variations_warehouses.waiting_quantity": "items_variation_variations_warehouses_waiting_quantity",

            
            #"production_order_id": null,
            #"display_id_original": null,
            #"costs_incurred": 0.0,
            #"prepaid_debt": null,
            #"transport_fee": 0,
            #"calculation_tax": {}
            #"custom_id":
            #"bill_images": [],
            #"export_accessories_id": null,
            #"received_at": "received_at",
            #"transaction_id": null,
            #"is_batch_shelf": null,
            #"auto_create_debts": null, 
            #"separate_by_display_ids": null,
            #"tags": null
            #"items.lots": "items.lots",
            #"items.measure_info": "items.measure_info",
            #"items.note_purchase": "items.note_purchase",
            #"items.number_of_batch": "items.number_of_batch",
            #"items.quantity_per_batch": "items.quantity_per_batch",
            #"items.tax_amount": "items.tax_amount",
            #"items.variation.product.is_published": "items.variation.product.is_published",
            #"items.variation.product.note": "items.variation.product.note",
            #"items.variation.product.note_product": "items.variation.product.note_product",
            #"items.variation.product.tags": "items.variation.product.tags",

}


VN_TZ = timezone(timedelta(hours=7))


def vn_to_unix(date_str):
    """Convert Vietnam local time string (UTC+7) to Unix timestamp (integer)."""
    dt = datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=VN_TZ)
    return int(dt.timestamp())


def load_data(start_date=None, end_date=None):
    """
    Load product data from Pancake API.
    If start_date / end_date are provided (Vietnam time), they are sent to the
    API as Unix timestamp params (startDate / endDate) to reduce pages fetched.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/purchases"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_entries = []
    page = 1
    page_size = 1000

    date_params = {}
    if start_date:
        date_params['startDate'] = vn_to_unix(start_date)
        print(f"  API startDate (unix): {date_params['startDate']}  ← {start_date} VN time")
    if end_date:
        date_params['endDate'] = vn_to_unix(end_date)
        print(f"  API endDate   (unix): {date_params['endDate']}  ← {end_date} VN time")

    print(f"Fetching data from API...")
    
    while True:
        try:
            params = {
                'api_key': api_key,
                'page': page,
                'page_size': page_size,
                **date_params,
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
    Filter entries based on inserted_at column.
    
    Args:
        entries: List of entries from API
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
        
    Returns:
        Filtered list of entries
    """
    if not start_date and not end_date:
        print("No date filters applied - using all data")
        return entries
    
    # Parse filter dates
    start_dt = datetime.strptime(start_date, "%Y-%m-%dT%H:%M:%S") if start_date else None
    end_dt = datetime.strptime(end_date, "%Y-%m-%dT%H:%M:%S") if end_date else None
    
    print(f"Filtering data by inserted_at...")
    if start_dt:
        print(f"  Start date: {start_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    if end_dt:
        print(f"  End date: {end_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    
    filtered_entries = []
    for entry in entries:
        inserted_at = entry.get("inserted_at")
        if not inserted_at:
            continue
        
        try:
            # Handle both formats: with and without microseconds
            if "." in inserted_at:
                entry_dt = datetime.strptime(inserted_at.split(".")[0], "%Y-%m-%dT%H:%M:%S")
            else:
                entry_dt = datetime.strptime(inserted_at, "%Y-%m-%dT%H:%M:%S")
            
            # Apply date filters
            if start_dt and entry_dt < start_dt:
                continue
            if end_dt and entry_dt > end_dt:
                continue
            
            filtered_entries.append(entry)
        except ValueError:
            # If date parsing fails, skip the entry
            continue
    
    print(f"  Filtered: {len(entries)} → {len(filtered_entries)} entries\n")
    return filtered_entries


def flatten_data(entries_raw):
    has_items = any(isinstance(o.get("items"), list) and o.get("items") for o in entries_raw)
    
    if has_items:
        df = json_normalize(
            entries_raw,
            record_path="items",
            meta=[col for col in entries_raw[0].keys() if col != "items"],
            record_prefix="items.",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        print(f"\nData Structure:")
        print(f"  Entries from API: {len(entries_raw)}")
        print(f"  Output Entries (rows): {len(df)}")
        print(f"  Note: Each output entry creates a separate row in the table")
        print(f"  Items details-level columns: {len([c for c in df.columns if c.startswith('items.')])}")
        print(f"  Entry-level columns: {len([c for c in df.columns if not c.startswith('items.')])}")
    else:
        df = json_normalize(entries_raw, sep=".", errors="ignore")
        print(f"\nData Structure:")
        print(f"  Entries from API: {len(entries_raw)}")
        print(f"  Rows to insert: {len(df)}")
    
    # Extract nested fields from 'user' object if it exists
    if 'user' in df.columns:
        df['user.name'] = df['user'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)
    
    # Extract nested fields from 'items.variation.variations_warehouses' array if it exists
    # This is an array, so we extract fields from the first element
    if 'items.variation.variations_warehouses' in df.columns:
        def get_warehouse_field(warehouses, field):
            if isinstance(warehouses, list) and len(warehouses) > 0:
                return warehouses[0].get(field) if isinstance(warehouses[0], dict) else None
            return None
        
        warehouse_fields = [
            'warehouse_id', 'actual_remain_quantity', 'pending_quantity', 
            'remain_quantity', 'returning_quantity', 'selling_avg', 
            'total_quantity', 'waiting_quantity'
        ]
        for field in warehouse_fields:
            df[f'items.variation.variations_warehouses.{field}'] = df['items.variation.variations_warehouses'].apply(
                lambda x: get_warehouse_field(x, field)
            )
    
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
        'inserted_at',
        'updated_at',
        'items_inserted_at',
        'items_variation_product_inserted_at',
        'items_variation_inserted_at',
        'items_variation_variations_warehouses_inserted_at',
        
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
    parser = argparse.ArgumentParser(description="Export Pancake POS product data to BigQuery")
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
    
    # Check if there are any products
    if not entries_raw or len(entries_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    # Filter data by date based on inserted_at column
    entries_raw = filter_data_by_date(entries_raw, start_date=start_date_arg, end_date=end_date_arg)
    
    # Check if there are any products after filtering
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

    # Determine output filename if not provided
    output_dir = OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if args.output:
        output_file = output_dir / args.output
    else:
        now_ts = datetime.now().strftime('%Y%m%d%H%M%S')
        output_file = output_dir / f"pancake_raw_purchases_list_{now_ts}.csv"

    export_data(df, str(output_file))
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()

# Placeholder for next edit
