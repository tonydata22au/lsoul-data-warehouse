#!/usr/bin/env python3
import json
import argparse
import warnings
import pytz
import requests
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

OutputPath = Path("G:/My Drive/03. CODE & DOCUMENTS/data_export_csv")


COLUMN_RENAME_MAP = {
   # Item info
    "item_id": "_item_id_",
    "item_product_id": "product_id",
    "item_variation_id": "variation_id",
    "item_quantity": "quantity_ordered",
    "item_return_quantity": "quantity_returned",
    "item_returning_quantity": "quantity_returning",
    "item_returned_count": "return_count",
    #"item_is_bonus_product": "is_bonus_item",
    #"item_is_composite": "is_composite_item",
    "item_is_wholesale": "is_wholesale",
    "item_is_discount_percent": "discount_is_percent",
    #"item_note": "item_notes",
    #"item_note_product": "item_product_notes",
    "item_one_time_product": "is_one_time_product",
    "item_added_to_cart_quantity": "cart_quantity",
    "item_exchange_count": "exchange_count",
    "item_discount_each_product": "unit_discount",
    "item_total_discount": "item_total_discount",
    #"item_same_price_discount": "same_price_discount",
    #"item_components": "composite_components",
    #"item_composite_item_id": "composite_parent_id",
    #"item_measure_group_id": "measure_group_id",
    
    # Product variation info
    "item_variation_info.name": "product_name",
    "item_variation_info.exact_price": "exact_price",
    "item_variation_info.retail_price": "retail_price",
    "item_variation_info.retail_price_original": "original_retail_price",
    "item_variation_info.avg_price": "average_price",
    "item_variation_info.last_imported_price": "last_import_price",
    #"item_variation_info.barcode": "product_barcode",
    #"item_variation_info.brand_id": "brand_id",
    #"item_variation_info.tax_rate": "tax_rate_percent",
    #"item_variation_info.weight": "product_weight",
    #"item_variation_info.display_id": "product_display_id",
    #"item_variation_info.product_display_id": "product_display_id",
    #"item_variation_info.category_ids": "product_category_ids",
    "item_variation_info.detail": "product_detail",
    "item_variation_info.fields": "product_fields",
    #"item_variation_info.images": "product_images",
    #"item_variation_info.is_upsale_product": "is_upsale",
    #"item_variation_info.measure_info": "measure_info",
    
    # Order IDs and Status
    "id": "order_id",
    "system_id": "system_id",
    "status": "status",
    "status_name": "status_name",
    #"sub_status": "sub_status",
    "inserted_at": "inserted_at",
    "updated_at": "updated_at",
    "received_at_shop": "is_received_at_shop",
    
    # Financial
    "order_currency":"order_currency",
    "total_price": "total_price",
    "total_price_after_sub_discount": "total_price_after_sub_discount",
    "total_discount": "total_discount",
    "total_quantity": "total_quantity",
    "shipping_fee": "shipping_fee",
    "fee_marketplace": "marketplace_fee",
    "partner_fee": "partner_fee",
    "surcharge": "surcharge_amount",
    "buyer_total_amount": "buyer_total_amount",
    "money_to_collect": "cod_money_to_collect",
    "cod": "cod",
    "tax": "tax_amount",
    
    # Payments
    "cash": "paid_cash",
    "prepaid": "prepaid_amount",
    #"prepaid_by_point.money": "prepaid_by_points",
    "transfer_money": "transfer_amount",
    "charged_by_card": "charged_by_card",
    "charged_by_momo": "charged_by_momo",
    "charged_by_qrpay": "charged_by_qrpay",
    "bank_payments": "bank_payments",
    "exchange_payment": "exchange_payment_info",
    "customer_pay_fee": "is_customer_paid_fee",
    
    # Shipping & Address
    "shipping_address.commune_name": "shipping_address_commune_name",
    "shipping_address.province_name": "shipping_address_province_name",
    #"bill_full_name": "billing_name",
    #"bill_phone_number": "billing_phone",
    #"bill_email": "billing_email",
    
    # Warehouse & Shop
    "warehouse_id": "warehouse_id",
    "warehouse_info.name": "warehouse_info_name",
    #"shop_id": "shop_id",
    "marketplace_id": "marketplace_id",
    
    # Links & Tracking
    #"link": "link",
    #"tracking_link": "tracking_link",
    "order_sources": "order_sources",
    "order_sources_name": "order_sources_name",
    "ad_id": "ad_id",
    "page_id": "page_id",
    #"page": "page_info",
    
    # Notes & Tags
    #"note": "notes",
    #"note_print": "print_notes",
    #"note_image": "image_notes",
    #"tags": "tags",
    
    # Customer Info
    "customer.currency": "customer_currency",
    "customer.customer_id": "customer_customer_id",
    "customer.succeed_order_count": "customer_succeed_order_count",
    "customer.inserted_at": "customer_inserted_at",
    "customer.is_block": "customer_is_block",
    "customer.updated_at": "customer_updated_at",
    "customer.order_count": "customer_order_count",
    "customer.returned_order_count": "customer_returned_order_count",
    "customer.purchased_amount": "customer_purchased_amount",
    "customer.last_order_at": "customer_last_order_at",
    "customer.gender": "customer_gender",
    
    # Assignment & Care (JSON Normalized)
    "assigning_seller.name": "assigning_seller_name",
    "assigning_seller.email": "assigning_seller_email",
    #"assigning_seller.id": "assigned_seller_id",
    "assigning_care.name": "assigning_care_name",
    "assigning_care.email": "assigning_care_email",
    #"assigning_care.id": "assigning_care_id",
    
    # Time tracking
    "time_assign_seller": "time_assigned_seller",
    "time_assign_care": "time_assigned_care",
    "time_send_partner": "time_sent_partner",
    
    # Returns & Exchange
    "is_exchange_order": "is_exchange_order",
    "exchange_value": "exchange_value",
    "returned_reason": "return_reason_code",
    "returned_reason_name": "return_reason",
    #"return_fee": "return_fee",
    
    # Marketing & UTM
    #"p_utm_source": "utm_source",
    #"p_utm_medium": "utm_medium",
    #"p_utm_campaign": "utm_campaign",
    #"p_utm_content": "utm_content",
    #"p_utm_term": "utm_term",
    #"p_utm_id": "utm_id",
    
    # Promotions & Features
    #"activated_promotion_advances": "activated_promotions",
    #"activated_combo_products": "activated_combos",
    #"levera_point": "levera_points",
    
    # Status Tracking
    #"status_history": "status_history",
    #"histories": "full_history",
    # last_editor (JSON Normalized)
    "last_editor.name": "last_editor_name",
    "last_editor.email": "last_editor_email",
    
    # Flags
    #"is_free_shipping": "is_free_shipping",
    #"is_livestream": "is_livestream_order",
    #"is_live_shopping": "is_live_shopping",
    #"is_smc": "is_smc",
    
    # Other
    #"conversation_id": "conversation_id",
    #"estimate_delivery_date": "estimated_delivery_date",
    #"currency": "currency",
    #"customer_needs": "customer_special_needs",
    #"botcake_info": "botcake_info",
    #"ads_source": "ads_source",
    #"marketer": "marketer_name",
    #"pke_mkter": "pke_marketer",
    
    #"creator" (JSON Normalized):
    "creator.name": "creator_name",
    "creator.email": "creator_email",
    
    #"account": "account_info",
    #"account_name": "account_name",
    "partner": "partner",
    "items_length": "items_count",
    #"post_id": "post_id",

    #"advanced_platform_fee" (JSON Normalized):
    "advanced_platform_fee.affiliate_commission": "advanced_platform_fee_affiliate_commission",
    "advanced_platform_fee.diff_shipping_fee": "advanced_platform_fee_diff_shipping_fee",
    "advanced_platform_fee.marketplace_voucher": "advanced_platform_fee_marketplace_voucher",
    "advanced_platform_fee.payment_fee": "advanced_platform_fee_payment_fee",
    "advanced_platform_fee.seller_transaction_fee": "advanced_platform_fee_seller_transaction_fee",
    "advanced_platform_fee.service_fee": "advanced_platform_fee_service_fee",
    #"advanced_platform_fee.sfp_service_fee": "advanced_platform_fee_sfp_service_fee",

    #"additional_info": "additional_info",
    #"tax": "tax_amount",
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
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/orders"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_orders = []
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
            
            orders = payload.get("data", [])
            if not orders:
                break
            
            all_orders.extend(orders)
            total_pages = payload.get("total_pages", 1)
            print(f"  Fetched page {page}/{total_pages}: {len(orders)} orders (total: {len(all_orders)})")
            
            # Check if there are more pages
            if len(orders) < page_size and page >= total_pages:
                break
            
            page += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"✓ Successfully fetched {len(all_orders)} orders from API\n")
    return all_orders


def flatten_data(orders_raw):
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    # Check if orders have items (array that needs to be exploded into rows)
    has_items = any(isinstance(o.get("items"), list) and o.get("items") for o in orders_raw)
    
    if has_items:
        # Normalize with items as record_path (each item becomes a row)
        # and include all order-level fields as meta
        df = json_normalize(
            orders_raw,
            record_path="items",
            meta=[
                'id', 'system_id', 'status', 'status_name', 'inserted_at', 'updated_at', 
                'received_at_shop','order_currency', 'total_price', 'total_price_after_sub_discount', 
                'total_discount', 'total_quantity', 'shipping_fee', 'fee_marketplace', 
                'partner_fee', 'surcharge', 'buyer_total_amount', 'money_to_collect', 
                'cod', 'tax', 'cash', 'prepaid', 'transfer_money', 'charged_by_card', 
                'charged_by_momo', 'charged_by_qrpay', 'bank_payments', 'exchange_payment', 
                'customer_pay_fee', ['shipping_address', 'commune_name'], 
                ['shipping_address', 'province_name'], 'warehouse_id',['warehouse_info','name'], 'marketplace_id', 
                'order_sources', 'order_sources_name', 'ad_id', 'page_id',
                ['customer','currency'], ['customer','customer_id'], ['customer','succeed_order_count'],
                ['customer','inserted_at'], ['customer','is_block'], ['customer','updated_at'],
                ['customer','order_count'], ['customer','returned_order_count'], ['customer','purchased_amount'],
                ['customer','last_order_at'], ['customer','gender'],
                ['assigning_seller', 'name'], ['assigning_seller', 'email'],
                ['assigning_care', 'name'], ['assigning_care', 'email'],
                'time_assign_seller', 'time_assign_care', 'time_send_partner',
                'is_exchange_order', 'exchange_value', 'returned_reason', 'returned_reason_name',
                ['last_editor', 'name'], ['last_editor', 'email'],
                ['creator', 'name'], ['creator', 'email'],
                'partner', 'items_length',
                ['advanced_platform_fee', 'affiliate_commission'],
                ['advanced_platform_fee', 'diff_shipping_fee'],
                ['advanced_platform_fee', 'marketplace_voucher'],
                ['advanced_platform_fee', 'payment_fee'],
                ['advanced_platform_fee', 'seller_transaction_fee'],
                ['advanced_platform_fee', 'service_fee']
            ],
            record_prefix="item_",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        
        print(f"\nData Structure:")
        print(f"  Orders from API: {len(orders_raw)}")
        print(f"  Order items (rows): {len(df)}")
        print(f"  Note: Each order item creates a separate row in the table")
        print(f"  Item-level columns: {len([c for c in df.columns if c.startswith('item_')])}")
        print(f"  Order-level columns: {len([c for c in df.columns if not c.startswith('item_')])}")
    else:
        # No items, just normalize the order data with all nested objects flattened
        df = json_normalize(orders_raw, sep=".", errors="ignore")
        
        print(f"\nData Structure:")
        print(f"  Orders from API: {len(orders_raw)}")
        print(f"  Rows to insert: {len(df)}")
    
    return df.copy()

def rename_and_reorder_columns(df):
    # Include all columns from COLUMN_RENAME_MAP, creating empty columns for missing data
    # This ensures consistent column structure across all exports
    new_df_dict = {}
    
    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
        else:
            # Create empty column for missing fields from API
            new_df_dict[new_col] = ''
    
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
        'inserted_at', 'updated_at', 'received_at_shop',
        'time_assigned_seller', 'time_assigned_care', 'time_sent_partner'
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
    for col in df.columns:
        df[col] = df[col].astype(str).replace(['nan', '{}','[]','None'], '')
    return df


def list_columns(df):
    print("\nAvailable columns:")
    for i, col in enumerate(df.columns, 1):
        new_name = COLUMN_RENAME_MAP.get(col, col)
        print(f"  {i:3d}. {col} → {new_name}")
    print(f"\nTotal: {len(df.columns)} columns\n")

def prepare_df_for_bigquery(df):
    """
    Prepare DataFrame for BigQuery by converting data types appropriately.
    Handles numeric columns, empty strings, and maintains data type integrity.
    Based on the BigQuery table schema in DDL/raw_order.txt
    """
    df_bq = df.copy()
    
    # Define columns that should be strings (even if they contain numbers)
    string_columns = [
        'order_item_id', 'product_id', 'variation_id', 'order_id',
        'original_retail_price', 'product_detail', 'product_fields',
        'product_name', 'status_name', 'shipping_address_commune_name', 'shipping_address_province_name',
        'bank_payments', 'partner', 'order_sources', 'order_sources_name',
        'assigning_seller_name', 'assigning_seller_email', 'assigning_care_name', 'assigning_care_email',
        'last_editor_name', 'last_editor_email', 'creator_name', 'creator_email',
        'return_reason', 'page_id', 'ad_id', 'system_id',
        # Item-level integers
        'quantity_ordered', 'quantity_returned', 'quantity_returning', 'return_count',
        'is_wholesale', 'discount_is_percent', 'is_one_time_product', 'cart_quantity',
        'exchange_count', 'unit_discount', 'item_total_discount', 'retail_price',
        'last_import_price',
        # Time columns
        'time_assigned_seller', 'time_assigned_care', 'time_sent_partner',
        'inserted_at', 'updated_at',
        # Order-level integers
        'status', 'is_received_at_shop',
        'total_price', 'total_price_after_sub_discount', 'total_discount', 'total_quantity',
        'shipping_fee', 'marketplace_fee', 'partner_fee', 'surcharge_amount',
        'cod_money_to_collect', 'cod', 'tax_amount',
        'paid_cash', 'prepaid_amount', 'transfer_amount', 'charged_by_card',
        'charged_by_momo', 'charged_by_qrpay', 'exchange_payment_info',
        'is_customer_paid_fee', 'items_count', 'warehouse_id', 'marketplace_id',
        'is_exchange_order', 'exchange_value', 'return_reason_code',
        # Platform fee integers
        'advanced_platform_fee_affiliate_commission', 'advanced_platform_fee_diff_shipping_fee',
        'advanced_platform_fee_marketplace_voucher', 'advanced_platform_fee_payment_fee',
        'advanced_platform_fee_seller_transaction_fee', 'advanced_platform_fee_service_fee',
        'quantity_ordered', 'quantity_returned', 'quantity_returning', 'return_count',
        'quantity_ordered', 'quantity_returned', 'quantity_returning', 'return_count',
        'is_wholesale', 'discount_is_percent', 'is_one_time_product', 'cart_quantity',
        'exchange_count', 'unit_discount', 'item_total_discount', 'retail_price',
        'last_import_price',
        # Time columns
        'time_assigned_seller', 'time_assigned_care', 'time_sent_partner',
        'inserted_at', 'updated_at',
        # Order-level integers
        'status', 'is_received_at_shop',
        'total_price', 'total_price_after_sub_discount', 'total_discount', 'total_quantity',
        'shipping_fee', 'marketplace_fee', 'partner_fee', 'surcharge_amount',
        'cod_money_to_collect', 'cod', 'tax_amount',
        'paid_cash', 'prepaid_amount', 'transfer_amount', 'charged_by_card',
        'charged_by_momo', 'charged_by_qrpay', 'exchange_payment_info',
        'is_customer_paid_fee', 'items_count', 'warehouse_id', 'marketplace_id',
        'is_exchange_order', 'exchange_value', 'return_reason_code',
        # Platform fee integers
        'advanced_platform_fee_affiliate_commission', 'advanced_platform_fee_diff_shipping_fee',
        'advanced_platform_fee_marketplace_voucher', 'advanced_platform_fee_payment_fee',
        'advanced_platform_fee_seller_transaction_fee', 'advanced_platform_fee_service_fee',
        'unit_price', 'average_price', 'buyer_total_amount'
    ]
    
    # Convert string columns (ensure they are strings)
    for col in string_columns:
        if col in df_bq.columns:
            df_bq[col] = df_bq[col].astype(str).replace(['nan', '{}','[]','None'], '')
    return df_bq

def export_data(df, output_file):
    # Convert all columns to object type to preserve empty strings
    for col in df.columns:
        df[col] = df[col].astype('object')
    # Export with UTF-8 encoding (with BOM for better Excel compatibility)
    # BOM helps Excel properly detect UTF-8 encoding for Vietnamese characters
    df.to_csv(output_file, index=False, encoding='utf-8-sig', na_rep='', quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS order data to BigQuery or CSV")
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
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    if args.All:
        # Cap at yesterday 23:59:59 (Vietnam time) when requesting "all" to avoid partial current-day data    
        now_vietnam = datetime.now(vietnam_tz)
        yesterday_vietnam = now_vietnam - timedelta(days=1)
        start_date_arg = None
        end_date_arg = yesterday_vietnam.strftime("%Y-%m-%dT23:59:59")
    elif args.start_date or args.end_date:
        start_date_arg = args.start_date
        end_date_arg = args.end_date
    else:
        # Default: 30 days ago to yesterday (Vietnam time)
        now_vn = datetime.now(vietnam_tz)
        end_vn = (now_vn - timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=0)
        start_vn = end_vn - timedelta(days=30)
        start_date_arg = start_vn.strftime("%Y-%m-%dT%H:%M:%S")
        end_date_arg = end_vn.strftime("%Y-%m-%dT%H:%M:%S")

    orders_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
   # Check if there are any orders
    if not orders_raw or len(orders_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(orders_raw)
    
    if args.list:
        list_columns(df)
        return
    
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = prepare_df_for_bigquery(df)
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
        output_file = output_dir / f"pancake_raw_order_list_{now_ts}.csv"

    export_data(df, output_file)
    print(f"✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()

# Placeholder for next edit
