#!/usr/bin/env python3
"""
Script to load order data from Pancake API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's order data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)

Usage:
    python3 local-run/pancake/data_export_order.py               # Get yesterday's order data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)
    python local-run/pancake/data_export_order.py --start-date 2026-07-14T00:00:00 --end-date 2026-07-14T23:59:59
    python3 local-run/pancake/data_export_order.py --All           # Get all order data with up to yesterday's date (Vietnam time)
    python3 src/local_run/pancake_order.py --All                    # Get all order data with up to yesterday's date (Vietnam time)
    python3 src/local_run/pancake_order.py                          # Get yesterday's order data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)
    python3 src/local_run/pancake_order.py --30days                 # Get order data from 30 days ago (T00:00:00) to yesterday (T23:59:59) in Vietnam time (UTC+7)
"""
import argparse
import os
import warnings
import requests
from datetime import datetime, timedelta, timezone
import pandas as pd
from pandas import json_normalize
import pytz
import urllib3
from pathlib import Path
from google.cloud import bigquery
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

# BigQuery config — this script is expected to run from local-run/<folder>/,
# where credentials/google-credentials.json is a sibling of the script's parent.
BASE_DIR = Path(__file__).resolve().parent.parent.parent
SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


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
    "item_is_discount_percent": "is_discount_percent",
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
    "order_currency": "order_currency",
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
    #"ad_id": "ad_id",
    #"page_id": "page_id",
    #"page": "page_info",
    
    # Notes & Tags
    "note": "notes",
    "note_print": "print_notes",
    #"note_image": "image_notes",
    "tags": "tags",
    
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
    Convert date string in format 'YYYY-MM-DDTHH:MM:SS' (Vietnam time) to Unix timestamp.
    
    Args:
        date_string: Date string in format '2024-01-01T00:00:00' in Vietnam time or None
        
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
    api_url = "https://pos.pages.fm/api/v1/shops/1942246959/orders"
    api_key = os.environ["PANCAKE_API_KEY"]
    all_orders = []
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
                'updateStatus': 'updated_at' # Use 'updated_at' to filter orders based on their last update time
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
                'order_sources', 'order_sources_name', 'note', 'note_print', 'tags',
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
        'inserted_at', 'updated_at',
        'time_assigned_seller', 'time_assigned_care', 'time_sent_partner', 'customer_inserted_at',
        'customer_updated_at', 'customer_last_order_at'
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

def insert_to_bigquery(df, project_id=None, dataset_id="raw_pancake", table_id="raw_order"):
    """
    Insert DataFrame into BigQuery table.
    
    Args:
        df: DataFrame to insert
        project_id: Google Cloud project ID (if None, uses default from environment)
        dataset_id: BigQuery dataset name
        table_id: BigQuery table name
    """
    # Count unique orders
    unique_orders = df['order_id'].nunique() if 'order_id' in df.columns else len(df)
    total_rows = len(df)
    
    # Initialize BigQuery client with service account credentials
    client = bigquery.Client(project=project_id, credentials=credentials)
    
    try:
        # Construct table reference
        table_ref = client.dataset(dataset_id).table(table_id)
        
        # Get existing table schema to match types
        try:
            existing_table = client.get_table(table_ref)
            
        except Exception as e:
            print(f"  Warning: Could not get existing table schema: {e}")
            print(f"  Proceeding with autodetect...")
        
        # Configure load job - let BigQuery autodetect schema
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",  # Appends without overwriting
            autodetect=False,  # Don't autodetect - use existing table schema
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,  # Allow relaxing required to nullable
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,  # Allow adding new fields
            ],
        )
        
        # Convert all columns to string to match BigQuery STRING schema
        for col in df.columns:
            df[col] = df[col].astype(str).replace('nan', '').replace('None', '')
        
        # Load data from DataFrame to BigQuery
        load_job = client.load_table_from_dataframe(
            df, table_ref, job_config=job_config
        )
        load_job.result()  # Wait for completion
        
        print(f"✓ Successfully loaded {load_job.output_rows} rows to {dataset_id}.{table_id} [{load_job.job_id}]")
        print(f"  Unique orders: {unique_orders}")
        print(f"  Total rows (order items): {total_rows}")
        
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")



def main():
    parser = argparse.ArgumentParser(description="Export Pancake POS entry data to BigQuery")
    parser.add_argument("--project-id", default=None, help="Google Cloud project ID (optional, uses default if not specified)")
    parser.add_argument("--All", action="store_true", help="Fetch all data without date filters")
    parser.add_argument("--30days", dest="last_30_days", action="store_true", help="Fetch from 30 days ago 00:00:00 to yesterday 23:59:59 (Vietnam time)")
    parser.add_argument("--start-date", default=None, help="Start date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None, help="End date in format YYYY-MM-DDTHH:MM:SS (e.g., 2024-12-31T23:59:59)")
    args = parser.parse_args()

    if args.last_30_days and (args.All or args.start_date or args.end_date):
        parser.error("--30days cannot be combined with --All, --start-date or --end-date")
    
    # Determine date range based on four options:
    # 1. --All flag: No date filters
    # 2. Manual dates: Use provided --start-date and --end-date
    # 3. --30days flag: 30 days ago 00:00:00 to yesterday 23:59:59
    # 4. Default: Yesterday 00:00:00 to 23:59:59
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
    elif args.last_30_days:
        # 30 days ago 00:00:00 to yesterday 23:59:59 (Vietnam time)
        now_vn = datetime.now(vietnam_tz)
        start_vn = (now_vn - timedelta(days=30)).replace(hour=0, minute=0, second=0, microsecond=0)
        end_vn = (now_vn - timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=0)
        start_date_arg = start_vn.strftime("%Y-%m-%dT%H:%M:%S")
        end_date_arg = end_vn.strftime("%Y-%m-%dT%H:%M:%S")
    else:
        # Default: yesterday only (Vietnam time)
        yesterday_vn = datetime.now(vietnam_tz) - timedelta(days=1)
        start_date_arg = yesterday_vn.strftime("%Y-%m-%dT00:00:00")
        end_date_arg = yesterday_vn.strftime("%Y-%m-%dT23:59:59")

    orders_raw = load_data(start_date=start_date_arg, end_date=end_date_arg)
    
   # Check if there are any orders
    if not orders_raw or len(orders_raw) == 0:
        print("0 entry found. No data to export.")
        return
    
    df = flatten_data(orders_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)
    
    insert_to_bigquery(df, project_id=args.project_id)

if __name__ == "__main__":
    main()

# Placeholder for next edit
