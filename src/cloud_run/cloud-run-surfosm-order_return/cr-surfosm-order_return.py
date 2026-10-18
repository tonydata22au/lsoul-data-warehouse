import argparse
import hashlib
import logging
import os
import time
import warnings
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
import pytz
import requests
import urllib3
from flask import Flask, json
from google.cloud import bigquery
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logging.basicConfig(level=logging.INFO)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

# API Configuration
API_KEY = os.environ["SURFOSM_API_KEY"]
API_URL_ORDER = "https://api-app.scaleup-fulfilment.com/openapi/return-documents/list"
API_URL_ORDER_DETAIL = "https://api-app.scaleup-fulfilment.com/openapi/order/{order_number}/return-details"


COLUMN_RENAME_MAP = {

       "order_number": "order_number",
        "external_order_id": "external_order_id",
        "channel": "channel",
        "shipping": "shipping",
        "total_returns": "total_returns",
                "returns.return_document_code": "returns_return_document_code",
                "returns.order_number": "returns_order_number",
                "returns.type_cancel": "returns_type_cancel",
                "returns.qty": "returns_qty",
                "returns.received": "returns_received",
                "returns.status": "returns_status",
              
                        "returns.detail_item.item_sku": "returns_detail_item_item_sku",
                        "returns.detail_item.item_code": "returns_detail_item_item_code",
                        "returns.detail_item.i_name": "returns_detail_item_i_name",
                        "returns.detail_item.lot_number": "returns_detail_item_lot_number",
                        "returns.detail_item.item_quantity": "returns_detail_item_item_quantity",
                        "returns.detail_item.status_item": "returns_detail_item_status_item"
}

def convert_datetime_format(dt_string):
    """
    Convert datetime from ISO format (2026-01-31T18:16:04.000Z) to %Y%m%d%H%M%S format (20260131181604).
    
    Args:
        dt_string: Datetime string in ISO format or empty string
    
    Returns:
        Datetime string in %Y%m%d%H%M%S format or empty string if input is empty/invalid
    """
    if not dt_string or dt_string == '' or pd.isna(dt_string):
        return ''
    
    try:
        # Parse ISO format datetime
        dt = datetime.strptime(dt_string.replace('Z', '+00:00').split('+')[0].split('.')[0], '%Y-%m-%dT%H:%M:%S')
        # Return in desired format
        return dt.strftime('%Y%m%d%H%M%S')
    except (ValueError, AttributeError):
        # Return original string if conversion fails
        return dt_string


def load_data_url_1(date=None):
    """
    Load order list from API to get order numbers for a specific date.
    
    Args:
        date: Date in format 'YYYY-MM-DD' (e.g., '2024-01-01'). If None, uses yesterday's date.
    """
    headers = {
        "x-api-key": API_KEY
    }

    all_orders = []
    page_num = 1
    page_size = 1000

    if not date:
        # Use yesterday's date if no date provided
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        date = yesterday
        print(f"  No date provided - using yesterday's date: {date}")
    
    while True:
        try:
            params = {
                'date': date,
                'page': page_num,
                'per_page': page_size,
            }

            response = requests.get(API_URL_ORDER, params=params, headers=headers, timeout=9999)
            response.raise_for_status()
            payload = response.json()
            
            # Extract order numbers from the data structure
            data = payload.get("data", {})
            order_numbers = data.get("order_numbers", [])
            if not order_numbers:
                break
            
            all_orders.extend(order_numbers)
            total_pages = data.get("total_pages", 1)
            total = data.get("total", 0)
            print(f"  Fetched page {page_num}/{total_pages}: {len(order_numbers)} order numbers (total: {len(all_orders)} of {total})")
            
            # Check if there are more pages
            has_next_page = data.get("has_next_page", False)
            if not has_next_page or page_num >= total_pages:
                break
            
            page_num += 1
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")
    
    print(f"  ✓ Fetched {len(all_orders)} order numbers for {date}\n")
    return all_orders


def fetch_order_details(order_numbers, order_date_mapping=None):
    """
    Fetch detailed order information for each order number.
    
    Args:
        order_numbers: List of order numbers to fetch details for
        order_date_mapping: Dictionary mapping order_number to parameter_date (optional)
    
    Returns:
        List of order detail dictionaries
    """
    headers = {
        "x-api-key": API_KEY
    }
    
    all_order_details = []
    total = len(order_numbers)
    
    print(f"Fetching order details for {total} orders...")
    
    for idx, order_num in enumerate(order_numbers, 1):
        try:
            url = API_URL_ORDER_DETAIL.format(order_number=order_num)
            response = requests.get(url, headers=headers, timeout=60)
            response.raise_for_status()
            order_detail_response = response.json()
            
            # Extract the actual order data from the 'data' field
            if order_detail_response.get('ok') and 'data' in order_detail_response:
                order_detail = order_detail_response['data']
                # Add parameter_date to the order detail if mapping exists
                if order_date_mapping and order_num in order_date_mapping:
                    order_detail['parameter_date'] = order_date_mapping[order_num]
                all_order_details.append(order_detail)
            else:
                print(f"  Warning: Invalid response for order {order_num}")
                continue
            
            if idx % 10 == 0 or idx == total:
                print(f"  Fetched {idx}/{total} order details")
                
        except requests.exceptions.RequestException as e:
            print(f"  Warning: Failed to fetch order {order_num}: {e}")
            continue
        except Exception as e:
            print(f"  Warning: Failed to parse order {order_num}: {e}")
            continue
    
    print(f"✓ Successfully fetched {len(all_order_details)} order return details\n")
    return all_order_details


def flatten_data(order_details_raw):
    """Flatten return order data, expanding nested fields and normalizing structure.
    
    This function properly handles:
    1. Multiple returns per order (explodes returns array)
    2. Multiple detail items per return (explodes detail_item array)
    
    Creates one row per returned item (detail_item level grain).
    """
    
    if not order_details_raw:
        return pd.DataFrame()
    
    all_rows = []
    
    for order in order_details_raw:
        # Get order-level fields
        order_number = order.get('order_number')
        external_order_id = order.get('external_order_id')
        channel = order.get('channel')
        shipping = order.get('shipping')
        total_returns = order.get('total_returns')
        parameter_date = order.get('parameter_date')
        
        returns_list = order.get('returns', [])
        
        if not returns_list:
            # No returns - create one row with order info only
            all_rows.append({
                'parameter_date': parameter_date,
                'order_number': order_number,
                'external_order_id': external_order_id,
                'channel': channel,
                'shipping': shipping,
                'total_returns': total_returns
            })
        else:
            # Iterate through each return
            for return_item in returns_list:
                # Get return-level fields
                return_document_code = return_item.get('return_document_code')
                return_order_number = return_item.get('order_number')
                type_cancel = return_item.get('type_cancel')
                qty = return_item.get('qty')
                received = return_item.get('received')
                status = return_item.get('status')
                
                detail_items = return_item.get('detail_item', [])
                
                if not detail_items:
                    # No detail items - create one row with return info
                    all_rows.append({
                        'parameter_date': parameter_date,
                        'order_number': order_number,
                        'external_order_id': external_order_id,
                        'channel': channel,
                        'shipping': shipping,
                        'total_returns': total_returns,
                        'returns.return_document_code': return_document_code,
                        'returns.order_number': return_order_number,
                        'returns.type_cancel': type_cancel,
                        'returns.qty': qty,
                        'returns.received': received,
                        'returns.status': status
                    })
                else:
                    # Iterate through each detail item (creates one row per item)
                    for detail in detail_items:
                        all_rows.append({
                            'parameter_date': parameter_date,
                            'order_number': order_number,
                            'external_order_id': external_order_id,
                            'channel': channel,
                            'shipping': shipping,
                            'total_returns': total_returns,
                            'returns.return_document_code': return_document_code,
                            'returns.order_number': return_order_number,
                            'returns.type_cancel': type_cancel,
                            'returns.qty': qty,
                            'returns.received': received,
                            'returns.status': status,
                            'returns.detail_item.item_sku': detail.get('item_sku'),
                            'returns.detail_item.item_code': detail.get('item_code'),
                            'returns.detail_item.i_name': detail.get('i_name'),
                            'returns.detail_item.lot_number': detail.get('lot_number'),
                            'returns.detail_item.item_quantity': detail.get('item_quantity'),
                            'returns.detail_item.status_item': detail.get('status_item')
                        })
    
    df = pd.DataFrame(all_rows)
    
    print(f"\nData Structure:")
    print(f"  Orders from API: {len(order_details_raw)}")
    print(f"  Rows in dataframe (after exploding returns and detail_items): {len(df)}")
    print(f"  Total columns: {len(df.columns)}")
    
    return df.copy()

def rename_and_reorder_columns(df):
    # Include all columns from COLUMN_RENAME_MAP, creating empty columns for missing data
    # This ensures consistent column structure across all exports
    new_df_dict = {}
    
    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
        else:
            # Create empty column for missing fields from API (with same length as df)
            new_df_dict[new_col] = pd.Series([''] * len(df), index=df.index)
    
    result_df = pd.DataFrame(new_df_dict)
    
    # Convert datetime columns from ISO format to %Y%m%d%H%M%S format
    datetime_columns = ['returns_received']
    for col in datetime_columns:
        if col in result_df.columns:
            result_df[col] = result_df[col].apply(convert_datetime_format)
    
    return result_df

def insert_to_bigquery(df, project_id=None, dataset_id="surfosm", table_id="raw_surfosm_order_return"):
    """Insert DataFrame into BigQuery."""
    
    # Convert all columns to string, but preserve None values
    for col in df.columns:
        df[col] = df[col].apply(lambda x: str(x) if x is not None else None)
   
    # Initialize BigQuery client with service account credentials
    client = bigquery.Client(project=project_id) if project_id else bigquery.Client()
    
    try:
        table_ref = client.dataset(dataset_id).table(table_id)
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            autodetect=False,
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,
            ],
        )
        load_job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
        load_job.result()
        print(f"  ✓ Successfully loaded {load_job.output_rows} rows into {dataset_id}.{table_id}")
    finally:
        # Ensure client is properly closed
        client.close()
        print("✓ BigQuery client closed")


def run_export(*, project_id=None, start_date=None, end_date=None, date=None, yesterday=False, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
    # Determine which dates to fetch
    dates_to_fetch = []
    
    if start_date and end_date:
        # Date range mode
        try:
            start = datetime.strptime(start_date, '%Y-%m-%d')
            end = datetime.strptime(end_date, '%Y-%m-%d')
            
            if start > end:
                error_msg = "Error: start_date must be before or equal to end_date"
                print(error_msg)
                return error_msg, 400
            
            # Generate all dates in range
            current = start
            while current <= end:
                dates_to_fetch.append(current.strftime('%Y-%m-%d'))
                current += timedelta(days=1)
            
            print(f"Fetching data for date range: {start_date} to {end_date} ({len(dates_to_fetch)} days)\n")
        except ValueError as e:
            error_msg = f"Error parsing dates: {e}"
            print(error_msg)
            return error_msg, 400
    elif date:
        # Single date mode
        dates_to_fetch = [date]
        print(f"Fetching data for single date: {date}\n")
    elif yesterday:
        # Yesterday only mode
        yesterday_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        dates_to_fetch = [yesterday_date]
        print(f"Fetching data for yesterday only: {yesterday_date}\n")
    else:
        # Default: 30 days from yesterday (start_date = 30 days ago from yesterday, end_date = yesterday)
        yesterday_dt = datetime.now() - timedelta(days=1)
        start_dt = yesterday_dt - timedelta(days=30)  # 30 days ago from yesterday
        
        current = start_dt
        while current <= yesterday_dt:
            dates_to_fetch.append(current.strftime('%Y-%m-%d'))
            current += timedelta(days=1)
        
        print(f"No date parameters provided - using default: 30 days from yesterday")
        print(f"  Date range: {start_dt.strftime('%Y-%m-%d')} to {yesterday_dt.strftime('%Y-%m-%d')} ({len(dates_to_fetch)} days)\n")
    
    # Step 1: Fetch order list to get order numbers for all dates
    # Track which date parameter was used for each order
    all_order_numbers = []
    order_date_mapping = {}  # Maps order_number -> parameter_date
    
    for date in dates_to_fetch:
        print(f"Fetching orders for date: {date}")
        order_numbers = load_data_url_1(date=date)
        all_order_numbers.extend(order_numbers)
        # Track which date parameter was used for each order
        for order_num in order_numbers:
            order_date_mapping[order_num] = date
    
    # Check if there are any order numbers
    if not all_order_numbers or len(all_order_numbers) == 0:
        msg = "\n0 order numbers found. No data to export."
        print(msg)
        return msg, 200
    
    print(f"\nTotal order numbers collected: {len(all_order_numbers)}")
    print(f"Ready to fetch details for {len(all_order_numbers)} returned orders")
    
    # Step 2: Fetch detailed information for each order
    order_details_raw = fetch_order_details(all_order_numbers, order_date_mapping)
    
    if not order_details_raw or len(order_details_raw) == 0:
        msg = "0 order details found. No data to export."
        print(msg)
        return msg, 200
    
    # Step 3: Flatten the detailed order data
    df = flatten_data(order_details_raw)
    
    if df.empty:
        msg = "No data to export after flattening."
        print(msg)
        return msg, 200
    
    # Preserve parameter_date column before processing (if it exists)
    parameter_date_col = df['parameter_date'].copy() if 'parameter_date' in df.columns else None
    
    # Step 4: Rename and reorder columns according to COLUMN_RENAME_MAP
    df = rename_and_reorder_columns(df)
    
    # Ensure final CSV contains only the columns defined in COLUMN_RENAME_MAP,
    # in the same order. Missing columns will be filled with empty strings.
    final_columns = list(COLUMN_RENAME_MAP.values())
    df = df.reindex(columns=final_columns, fill_value='')
    
    # Add parameter_date column at the beginning if it was present
    if parameter_date_col is not None:
        df.insert(0, 'parameter_date', parameter_date_col)
    
    # Step 5: Insert to BigQuery (unless dry_run mode)
    if dry_run:
        msg = f"DRY RUN: Would insert {len(df)} rows to BigQuery"
        print(f"\n{msg}")
        print(f"Preview of first 5 rows:\n{df.head()}")
        return msg, 200
    else:
        try:
            insert_to_bigquery(df, project_id=project_id)
            success_msg = f"Successfully exported {len(df)} orders to BigQuery"
            print(f"\n✓ {success_msg}")
            return success_msg, 200
        except Exception as e:
            error_msg = f"Failed to insert to BigQuery: {e}"
            print(f"\n✗ {error_msg}")
            logging.exception("BigQuery insertion failed")
            return error_msg, 500


app = Flask(__name__)


@app.route("/")
def run():
    logging.info("Triggering Surfosm returned order data export (HTTP)...")
    try:
        # Get project_id from environment variable (required for Cloud Run)
        project_id = os.environ.get('GCP_PROJECT')
        
        # Run export with default settings (30 days from yesterday)
        message, status = run_export(project_id=project_id)
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500


def main():
    parser = argparse.ArgumentParser(description="Export Surfosm returned order data to BigQuery")
    parser.add_argument("--project_id", default=None, help="GCP Project ID for BigQuery")
    parser.add_argument("--yesterday", action="store_true", help="Fetch only yesterday's date (single day)")
    parser.add_argument("--date", default=None, help="Single date in format YYYY-MM-DD (e.g., 2024-01-01)")
    parser.add_argument("--start_date", default=None, help="Start date for date range in format YYYY-MM-DD (e.g., 2024-01-01)")
    parser.add_argument("--end_date", default=None, help="End date for date range in format YYYY-MM-DD (e.g., 2024-01-03)")
    parser.add_argument("--dry_run", action="store_true", help="Preview data without inserting to BigQuery")
    parser.add_argument("--http", action="store_true", help="Run as HTTP server (Cloud Run mode)")
    
    args = parser.parse_args()

    # If HTTP mode, start Flask server
    if args.http:
        port = int(os.environ.get('PORT', 8080))
        logging.info(f"Starting HTTP server on port {port}...")
        app.run(host='0.0.0.0', port=port)
    else:
        # CLI mode - run export and exit
        message, status = run_export(
            project_id=args.project_id,
            start_date=args.start_date,
            end_date=args.end_date,
            date=args.date,
            yesterday=args.yesterday,
            dry_run=args.dry_run,
        )
        print(f"\n{message}")
        exit(0 if status == 200 else 1)


if __name__ == "__main__":
    main()
