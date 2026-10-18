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
            "inserted_at": "inserted_at",
            "id": "transaction_id",
            "ref_id": "ref_id",
            "status": "status",
            "type_transaction": "type_transaction",
            "name": "name",
            "display_id": "display_id",
            "account": "account",
            #creator (JSON NORMALIZE)
            "creator.name": "creator_name",
            "creator_id": "creator_id",
            "posted_at": "posted_at",
            "is_canceled": "is_canceled",
            "advertising_cost_id": "advertising_cost_id",
            "warehouse_id": "warehouse_id",
            "amount": "amount",
            "is_accounting": "is_accounting",
            "ref_display_id": "ref_display_id",
            "is_locked": "is_locked",
            "payments": "payments",
            "currency": "currency",
            "source": "source",
            "is_removed": "is_removed",
            "is_locked_by_user": "is_locked_by_user",
            "order.id": "order_id",
            "order.display_id": "order_display_id",
            "order.inserted_at": "order_inserted_at",
            "order.account": "order_account",
            "order.cod": "order_cod",
            "order.order_sources": "order_sources",
            "order.partner_id": "order_partner_id",
            "order.received_at_shop": "order_received_at_shop",
            "order.return_money": "order_return_money",
            "order.return_transfer_money": "order_return_transfer_money",
                
            # Shipping & Address (JSON NORMALIZE)
            "order.shipping_address.commnue_name": "shipping_address_commnue_name",
            "order.shipping_address.province_name": "shipping_address_province_name",
                
             #third_party_infomation (JSON NORMALIZE)
            "order.third_party_infomation.name": "order_third_party_information_name",
            "order.custom_id": "order_custom_id",
            # items (JSON NORMALIZE)
                "order.items.id": "order_item_id",
                "order.items.inserted_at": "order_item_inserted_at",
                "order.items.returned_count": "order_item_returned_count",
                "order.items.returned_count": "order_item_returned_count",     
                "order.items.one_time_product": "order_item_one_time_product",
                "order.items.is_fixed_prices": "order_item_is_fixed_prices",
                "order.items.returning_quantity": "order_item_returning_quantity",
                "order.items.is_wholesale": "order_item_is_wholesale",
                "order.items.quantity": "order_item_quantity",
                "order.items.variation_warehouse_id": "order_item_variation_warehouse_id",
                "order.items.discount": "order_item_discount",
                "order.items.assigning_seller_id": "order_items_assigning_seller_id",
                "order.items.product_id": "order_item_product_id",
                "order.items.added_to_cart_quantity": "order_item_added_to_cart_quantity",
                "order.items.parent_item_id": "order_item_parent_item_id",
                "order.items.discount_each_product": "order_item_discount_each_product",
                "order.items.add_to_cart": "order_item_add_to_cart",
                "order.items.is_discount_percent": "order_item_is_discount_percent",
                "order.items.variation_id": "order_item_variation_id",
                # variation_info (JSON NORMALIZE)
                "order.items.variation_info.id": "order_item_variation_info_id",           
                "order.items.variation_info.inserted_at": "order_item_variation_info_inserted_at",
                "order.items.variation_info.custom_id": "order_item_variation_info_custom_id",
                "order.items.variation_info.supplier_product_ids": "order_item_variation_info_supplier_product_ids",
                "order.items.variation_info.wholesale_price": "order_item_variation_info_wholesale_price",
                "order.items.variation_info.name": "order_item_variation_info_name",
                "order.items.variation_info.price_at_counter": "order_item_variation_info_price_at_counter",
                "order.items.variation_info.exact_price": "order_item_variation_info_exact_price",
                "order.items.variation_info.retail_price_by_currency": "order_item_variation_info_retail_price_by_currency",
                "order.items.variation_info.type": "order_item_variation_info_type",
                "order.items.variation_info.images": "order_item_variation_info_images",
                "order.items.variation_info.sort_variation_attributes": "order_item_variation_info_sort_variation_attributes",
                "order.items.variation_info.wholesale_price_original": "order_item_variation_info_wholesale_price_original",
                "order.items.variation_info.retail_price": "order_item_variation_info_retail_price",
                "order.items.variation_info.retail_price_by_weight": "order_item_variation_info_retail_price_by_weight",
                "order.items.variation_info.in_promotions": "order_item_variation_info_in_promotions",
                "order.items.variation_info.retail_price_currency_original": "order_item_variation_info_retail_price_currency_original",
                "order.items.variation_info.fields": "order_item_variation_info_fields",
                "order.items.variation_info.weight": "order_item_variation_info_weight",
                "order.items.variation_info.detail": "order_item_variation_info_detail",
                "order.items.variation_info.last_imported_price": "order_item_variation_info_last_imported_price",
                "order.items.variation_info.retail_price_wholesale_original": "order_item_variation_info_retail_price_wholesale_original",
                "order.items.variation_info.is_sell_negative": "order_item_variation_info_is_sell_negative",
                "order.items.variation_info.tax_rate": "order_item_variation_info_tax_rate",
                "order.items.variation_info.product_id": "order_item_variation_info_product_id",
                "order.items.variation_info.is_sell_negative_variation": "order_item_variation_info_is_sell_negative_variation",
                "order.items.variation_info.avg_price": "order_item_variation_info_avg_price",
                   
            #"supplier_or_customer": null,
            #"transaction_ref_id": null,
            #"shop_id": "shop_id",
            #"images": null,
            #"note": "note",
            #"tag_ids": [],
            #"supplier_products_id": null,
            #"auto_transfer_debt": true,
            #"table_name": "shop_transactions_order",
                        #"order.items.hide_product_name": "order_item_hide_product_name",
                        #"order.items.note_product": "order_item_note_product",
                        #"order.items.note_product_internal": null,
                        #"order.items.quantity_by_combo_products": "order_item_quantity_by_combo_products",
                        #"order.items.bonus_variations": [],
                        #"order.items.components": null,
                        #"order.items.measure_group_id": null,
                        #"order.items.limit_quantity_to_warn": 0,
                        #"order.items.composite_item_id": null,
                        # "bonus_products": [],
                        # "variations_warehouses": [],
                        # "manipulation_warehouses": [],
                        #"order.items.inks": [],
                        #"order.items.page":
                        #"order.items.bonus_each_product": false,
                        #"order.items.keyword_product": "",
                        #"order.items.is_bonus_product": false,
                        #"order.items.is_composite": false,                  
                        #"order.items.note": null,      
                             #"order.items.warning_by_variation": "order_item_warning_by_variation",
                             #"order.items.actual_variation_info": "order_items_actual_variation_info",
                             #"order.items.part_returning_quantity": "order_item_part_returning_quantity",
                             #"order.items.is_price_by_weight": "order_items_is_price_by_weight",
                             #"order.items.exchange_count": "order_items_exchange_count",
                             #"order.items.list_orders_returned": "order_items_list_orders_returned",
                             #"ignore_awarded_point": null,
                             #"materials": null,
                             #"shop_warranty_policy": null,
                             #"shop_warranty_policy_id": null,
                             #"warranty_period": null,
                             #"is_livestream_price": null,
                             #"free_from_referral_code": null,
                             #"service_info": null,
                             #"is_upsale_product": null,
                             #"bonus_from_items": null,
                             #"barcode": "V24091624-1"
                             #"order.items.variation_info.measure_info": "order_item_variation_info_measure_info",
                             #"order.items.variation_info.price_table": "order_item_variation_info_price_table",
                             #"order.items.variation_info.wholesale_price2": "order_item_variation_info_wholesale_price2",
                             #"order.items.variation_info.brand_id": null,
                             #"order.items.variation_info.keyword": null,
                            #"order.items.variation_info.category_ids": "order_item_variation_info_category_ids",
                            #"order.items.variation_info.pre_order_item_id": "order_item_variation_info_pre_order_item_id",
                            #"order.items.variation_info.size": "order_item_variation_info_size",
                            #"order.items.variation_info.one_time_product_id": "order_item_variation_info_one_time_product_id",
                            #"order.items.variation_info.retail_price_original": "order_item_variation_info_retail_price_original",
                            # "order.items.variation_info.is_price_contact": "order_item_variation_info_is_price_contact",
                            #"order.items.variation_info.product_tags": "order_item_variation_info_product_tags",
                            #"order.items.variation_info.is_accessory": "order_item_variation_info_is_accessory",
                            #"order.items.variation_info.pre_order_price": "order_item_variation_info_pre_order_price",
                            #"order.items.variation_info.limit_quantity_to_warn": "order_item_variation_info_limit_quantity_to_warn",
                            #"order.items.variation_info.addition_price": "order_item_variation_info_addition_price",
            #"shop_customer_id": null,
            #"payment_debts_to_suppliers": false,
            #"time_incurred": null

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
    Load product data from Pancake API.
    
    Args:
        start_date: Start date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-01-01T00:00:00'). If None, not used.
        end_date: End date in format 'YYYY-MM-DDTHH:MM:SS' (e.g., '2024-12-31T23:59:59'). If None, not used.
    """
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/transactions"
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
                params['startDateTime'] = start_datetime
            if end_datetime:
                params['endDateTime'] = end_datetime

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
    entries_with_order = [e for e in entries_raw if isinstance(e.get("order"), dict) and isinstance(e.get("order", {}).get("items"), list) and e.get("order", {}).get("items")]
    entries_without_order = [e for e in entries_raw if e not in entries_with_order]
    
    if entries_with_order:
        # Normalize with order.items as record_path (each item becomes a row)
        # and include all transaction-level fields as meta
        df_with_items = json_normalize(
            entries_with_order,
            record_path=["order", "items"],
            meta=[col for col in entries_with_order[0].keys() if col != "order"] + 
                 [["order", col] for col in entries_with_order[0].get("order", {}).keys() if col != "items"],
            record_prefix="order.items.",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        
        print(f"\nData Structure:")
        print(f"  Entries with orders from API: {len(entries_with_order)}")
        print(f"  Order items (rows): {len(df_with_items)}")
        print(f"  Note: Each order item creates a separate row in the table")
        print(f"  Item-level columns: {len([c for c in df_with_items.columns if c.startswith('order.items.')])}")
        
        if entries_without_order:
            # Also normalize entries without orders
            df_without_items = json_normalize(entries_without_order, sep=".", errors="ignore")
            print(f"  Entries without orders: {len(entries_without_order)} (rows: {len(df_without_items)})")
            
            # Combine both dataframes, filling missing columns with None
            df = pd.concat([df_with_items, df_without_items], ignore_index=True, sort=False)
            print(f"  Total rows: {len(df)}")
        else:
            df = df_with_items
    else:
        # No items, just normalize the transaction data with all nested objects flattened
        df = json_normalize(entries_raw, sep=".", errors="ignore")
        
        print(f"\nData Structure:")
        print(f"  Entries from API: {len(entries_raw)}")
        print(f"  Rows to insert: {len(df)}")

     # Extract nested fields from 'shipping_address' object if it exists
    if 'creator' in df.columns:
        df['creator.name'] = df['creator'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)
    
     # Extract nested fields from 'shipping_address' object if it exists
    if 'order.shipping_address' in df.columns:
        df['order.shipping_address.commnue_name'] = df['order.shipping_address'].apply(lambda x: x.get('commnue_name') if isinstance(x, dict) else None)
        df['order.shipping_address.province_name'] = df['order.shipping_address'].apply(lambda x: x.get('province_name') if isinstance(x, dict) else None)
    
    # Extract nested fields from 'third_party_infomation' object if it exists
    if 'order.third_party_infomation' in df.columns:
        df['order.third_party_infomation.name'] = df['order.third_party_infomation'].apply(lambda x: x.get('name') if isinstance(x, dict) else None)
    
    # Extract nested fields from 'order.items.variation_info' if it exists
    # variation_info can be either a dict or an array with one dict element
    if 'order.items.variation_info' in df.columns:
        def get_variation_info_field(variation_info, field):
            # Handle both dict and list formats
            if isinstance(variation_info, dict):
                return variation_info.get(field)
            elif isinstance(variation_info, list) and len(variation_info) > 0:
                return variation_info[0].get(field) if isinstance(variation_info[0], dict) else None
            return None
        
        variation_info_fields = [
            'id', 'inserted_at', 'custom_id', 'supplier_product_ids', 'wholesale_price', 'name', 'price_at_counter',
            'exact_price', 'retail_price_by_currency', 'type', 'images', 'sort_variation_attributes', 'wholesale_price_original', 'retail_price', 
            'retail_price_currency_original',
            'fields', 'weight', 'detail', 'last_imported_price', 'retail_price_wholesale_original', 'retail_price_original', 'is_price_contact',
            'is_sell_negative', 'tax_rate','product_id', 'is_sell_negative_variation', 'avg_price'
        ]
        for field in variation_info_fields:
            df[f'order.items.variation_info.{field}'] = df['order.items.variation_info'].apply(
                lambda x: get_variation_info_field(x, field)
            )
    
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
        'inserted_at', 'posted_at', 'order_inserted_at', 'order_items_inserted_at',
        'order_items_variation_info_inserted_at'
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
        output_file = output_dir / f"pancake_raw_transaction_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")

if __name__ == "__main__":
    main()

# Placeholder for next edit
