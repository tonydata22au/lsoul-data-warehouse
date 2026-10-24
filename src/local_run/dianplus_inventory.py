#!/usr/bin/env python3
"""
Script to load inventory data from Dianplus API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's inventory from T00:00:00 to T23:59:59 in shanghai time

Usage:
    python3 local-run/dianplus.cn/dianplus-inventory.py               # Get yesterday's inventory from T00:00:00 to T23:59:59 in shanghai time
    python3 local-run/dianplus.cn/dianplus-inventory.py --start_date 2026-01-01T00:00:00 --end_date 2026-05-26T23:59:59
    python3 local-run/dianplus.cn/dianplus-inventory.py --ALL           # Get all inventory with no date filter (use with caution)
    python3 src/local_run/dianplus_inventory.py                    # Get yesterday's inventory
    python3 src/local_run/dianplus_inventory.py --start_date 2026-01-01T00:00:00 --end_date 2026-05-26T23:59:59
    python3 src/local_run/dianplus_inventory.py --ALL              # Get all inventory with no date filter (use with caution)
"""
import json
import os
import argparse
import warnings
import time
import pytz
import requests
import hashlib
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
from dotenv import load_dotenv
from google.cloud import bigquery
from google.oauth2 import service_account

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

# API Configuration
MERCHANT_CODE = "13939"
APP_KEY = os.environ["DIANPLUS_APP_KEY"]
APP_SECRET = os.environ["DIANPLUS_APP_SECRET"]
VERSION = "1.0"
AUTH_URL = "https://open.dianplus.cn/api/product/rs/isv/auth/get_token"
API_URL = "https://open.dianplus.cn:443/api/vpc/rs/isv/inventory/getInvs"

# Global variable to cache the token
_cached_token = None
_token_expiry = None

# BigQuery config — this script is expected to run from local-run/<folder>/,
# where credentials/google-credentials.json is a sibling of the script's parent.
BASE_DIR = Path(__file__).resolve().parent.parent.parent
SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


COLUMN_RENAME_MAP = {
                "brandId": "brandId",
                "storageId": "storageId",
                "spuId": "spuId",
                "spuCode": "spuCode",
                "skuId": "skuId",
                "skuCode": "skuCode",
                "realNum": "realNum",
                "lockNum": "lockNum",
                "canUseNum": "canUseNum",
                "frozenNum": "frozenNum",
                "transitNum": "transitNum",
                "defectNum": "defectNum"
}

def get_auth_token():
    """
    Get authentication token from Dianplus API.
    Caches the token to avoid unnecessary API calls.
    Implements retry logic with exponential backoff for network issues.
    
    Returns:
        Token string from the API response
        
    Raises:
        Exception if authentication fails after all retries
    """
    global _cached_token, _token_expiry
    
    # Check if we have a cached token that hasn't expired
    # Assuming token is valid for at least 1 hour, refresh if less than 5 minutes left
    if _cached_token and _token_expiry and datetime.now() < _token_expiry:
        print(f"Using cached authentication token")
        return _cached_token
    
    print("Fetching new authentication token...")
    
    params = {
        "appId": APP_KEY,
        "appSecret": APP_SECRET
    }
    
    # Retry configuration
    max_retries = 3
    retry_count = 0
    base_timeout = 60  # Increased from 30 to 60 seconds
    
    while retry_count < max_retries:
        try:
            # Calculate timeout with exponential backoff
            current_timeout = base_timeout * (2 ** retry_count)
            
            if retry_count > 0:
                wait_time = 2 ** retry_count  # Exponential backoff: 2, 4, 8 seconds
                print(f"Retry {retry_count}/{max_retries} after {wait_time}s wait... (timeout: {current_timeout}s)")
                time.sleep(wait_time)
            
            response = requests.get(AUTH_URL, params=params, timeout=current_timeout, verify=False)
            
            if response.status_code != 200:
                raise Exception(f"Authentication failed with status code: {response.status_code}")
            
            data = response.json()
            
            if data.get("resultCode") != "success":
                error_msg = data.get('exceptionMessage') or 'Unknown authentication error'
                raise Exception(f"Authentication API error: {error_msg}")
            
            token = data.get("resultObject")
            
            if not token:
                raise Exception("No token received from authentication API")
            
            # Cache the token (set expiry to 55 minutes from now to be safe)
            _cached_token = token
            _token_expiry = datetime.now() + timedelta(minutes=55)
            
            print(f"✓ Successfully obtained authentication token")
            return token
            
        except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as e:
            retry_count += 1
            if retry_count >= max_retries:
                raise Exception(f"Authentication request failed after {max_retries} retries. Network issue: {e}")
            print(f"⚠ Network timeout/error: {e}")
            
        except requests.exceptions.RequestException as e:
            raise Exception(f"Authentication request failed: {e}")

def calculate_sign(app_id, brand_id, page_num, page_size, time_stamp):
    """
    Calculate MD5 sign for API authentication.
    Parameters are concatenated in alphabetical order: app, app_Id, brandId, pageNum, pageSize, time_stamp, version
    
    Args:
        app_id: Application ID
        brand_id: Brand/Merchant ID
        page_num: Page number
        page_size: Page size
        time_stamp: Timestamp in format YYYYMMDDHHMMSS
        
    Returns:
        MD5 hash string in hexadecimal format
    """
    # Construct the raw string with parameters in alphabetical order
    raw = (
        f"app{APP_SECRET}"
        f"app_Id{app_id}"
        f"brandId{brand_id}"
        f"pageNum{page_num}"
        f"pageSize{page_size}"
        f"time_stamp{time_stamp}"
        f"version{VERSION}"
    )
    
    print(f"Raw string before MD5 encryption: {raw}")
    
    # Calculate MD5 hash
    sign = hashlib.md5(raw.encode('utf-8')).hexdigest()
    print(f"Sign after MD5 encryption: {sign}")
    return sign


def parse_date_to_unix(date_string):
    """
    Convert date string in format 'YYYY-MM-DDTHH:MM:SS' (Vietnam timezone) to format 'YYYY-MM-DD HH:MM:SS' Asia/Shanghai timezone.
    
    Args:
        date_string: Date string in format '2024-01-01T00:00:00' in Vietnam time or None
        
    Returns:
        Date string in Shanghai timezone or None
    """
    if not date_string or date_string.strip() == "":
        return None
    
    try:
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        dt_vietnam = vietnam_tz.localize(dt)
        shanghai_tz = pytz.timezone('Asia/Shanghai')
        dt_shanghai = dt_vietnam.astimezone(shanghai_tz)
        return dt_shanghai.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")


def load_data(start_time=None, end_time=None):
    """
    Load inventory data from Dianplus API.
    
    Args:
        start_time: Start time in format 'YYYY-MM-DD HH:MM:SS' (Shanghai timezone)
        end_time: End time in format 'YYYY-MM-DD HH:MM:SS' (Shanghai timezone)

    Returns:
        DataFrame containing inventory data
    """
    # Get authentication token
    token = get_auth_token()
    
    headers = {
        "Token": token
    }
    
    all_rows = []
    page_num = 1
    page_size = 2000
    
    print(f"Fetching inventory data from Dianplus API (startModified={start_time}, endModified={end_time})...")
    
    while True:
        # Generate timestamp for this request
        time_stamp = datetime.now(pytz.timezone('Asia/Shanghai')).strftime("%Y%m%d%H%M%S")
        print(f"Request timestamp: {time_stamp}")
        
        # Calculate sign
        sign = calculate_sign(APP_KEY, MERCHANT_CODE, str(page_num), str(page_size), time_stamp)
        
        params = {
            "app_id": APP_KEY,
            "brandId": MERCHANT_CODE,
            "pageNum": page_num,
            "pageSize": page_size,
            "startModified": start_time,
            "endModified": end_time,
            "time_stamp": time_stamp,
            "version": VERSION,
            "sign": sign
        }
        
        try:
            # Use POST with form data (not JSON)
            print(f"Request params: {json.dumps(params, indent=2, ensure_ascii=False)}")
            response = requests.post(API_URL, headers=headers, data=params, timeout=69)
            print(f"Response status code: {response.status_code}")
            
            if response.status_code != 200:
                print(f"Error fetching data: {response.status_code} - {response.text}")
                break
            
            data = response.json()
            
            if data.get("resultCode") != "success":
                error_msg = data.get('exceptionMessage') or 'Unknown error'
                print(f"API error: {error_msg}")
                break
            
            raw_data = data.get("resultObject", {}).get("results", [])
            
            if not raw_data:
                print(f"No more data to fetch on page {page_num}.")
                break
            
            all_rows.extend(raw_data)
            print(f"Fetched page {page_num} with {len(raw_data)} records. Total so far: {len(all_rows)}")
            
            page_num += 1
            
        except requests.exceptions.RequestException as e:
            print(f"Request error: {e}")
            break
    
    if not all_rows:
        print("No data fetched.")
        return pd.DataFrame()
    
    # Create DataFrame from raw data
    df = pd.DataFrame(all_rows)
    
    # Rename and reorder columns to match COLUMN_RENAME_MAP
    df = rename_and_reorder_columns(df)
    
    print(f"Total inventory records fetched: {len(df)}")
    return df


def rename_and_reorder_columns(df):
    """
    Rename columns according to COLUMN_RENAME_MAP and filter to only include columns specified in the map.
    Columns are reordered to match the map's order. Any columns not in the map are excluded.
    
    Args:
        df: DataFrame with flattened column names from json_normalize
    
    Returns:
        DataFrame with only renamed and reordered columns from COLUMN_RENAME_MAP
    """
    # First, rename columns that exist in the dataframe
    rename_dict = {k: v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns}
    df_renamed = df.rename(columns=rename_dict)
    
    # Get the desired column order from COLUMN_RENAME_MAP (the values)
    desired_order = list(COLUMN_RENAME_MAP.values())
    
    # Only include columns from COLUMN_RENAME_MAP (in order)
    final_column_order = [col for col in desired_order if col in df_renamed.columns]
    
    # Reorder the dataframe and only keep specified columns
    return df_renamed[final_column_order]

def insert_to_bigquery(df, project_id=None, dataset_id="dianplus", table_id="raw_dianplus_inventory"):
    """Insert DataFrame into BigQuery."""
    # Convert all columns to string to match BQ schema
    df = df.astype(str)
    client = bigquery.Client(project=project_id, credentials=credentials)
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
        client.close()

def main():
    """
    Main function to fetch inventory data and insert to BigQuery.
    """
    parser = argparse.ArgumentParser(description='Fetch inventory data from Dianplus API')
    parser.add_argument('--start_date', type=str, help='Start date in format YYYY-MM-DDTHH:MM:SS (Vietnam timezone)', default=None)
    parser.add_argument('--end_date', type=str, help='End date in format YYYY-MM-DDTHH:MM:SS (Vietnam timezone)', default=None)
    parser.add_argument('--ALL', action='store_true', help='Fetch all inventory with no date filter')

    args = parser.parse_args()

    if args.ALL:
        print("Fetching ALL inventory with no date filter...")
        df_final = load_data(start_time=None, end_time=None)
        if not df_final.empty:
            inserted_at = datetime.now(pytz.timezone('Asia/Shanghai')).strftime("%Y%m%d") + "000000"
            df_final['inserted_at'] = inserted_at
            print(f"\nInserting {len(df_final)} rows to BigQuery...")
            insert_to_bigquery(df_final)
            print(f"✓ Total rows processed: {len(df_final)}")
        else:
            print("\n✗ No data to insert.")
        return

    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    shanghai_tz = pytz.timezone('Asia/Shanghai')

    if args.end_date:
        end_time = parse_date_to_unix(args.end_date)
    else:
        # Default: yesterday 23:59:59 in Vietnam timezone, converted to Shanghai
        end_date_vn = datetime.now(vietnam_tz) - timedelta(days=1)
        end_date_vn = end_date_vn.replace(hour=23, minute=59, second=59)
        end_time = end_date_vn.astimezone(shanghai_tz).strftime("%Y-%m-%d %H:%M:%S")

    if args.start_date:
        start_time = parse_date_to_unix(args.start_date)
    else:
        # Default: yesterday 00:00:00 in Vietnam timezone, converted to Shanghai
        if args.end_date:
            dt = datetime.strptime(args.end_date, "%Y-%m-%dT%H:%M:%S")
            dt_vietnam = vietnam_tz.localize(dt)
        else:
            dt_vietnam = datetime.now(vietnam_tz) - timedelta(days=1)
        start_date_vn = dt_vietnam.replace(hour=0, minute=0, second=0)
        start_time = start_date_vn.astimezone(shanghai_tz).strftime("%Y-%m-%d %H:%M:%S")

    print(f"Date range: {start_time} to {end_time} (Shanghai timezone)")

    # Derive inserted_at from end_time in YYYYMMDDHHMMSS format
    inserted_at = datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S").strftime("%Y%m%d%H%M%S")

    # Fetch inventory data
    df_final = load_data(start_time, end_time)

    # Insert to BigQuery
    if not df_final.empty:
        df_final['inserted_at'] = inserted_at
        print(f"\nInserting {len(df_final)} rows to BigQuery...")
        insert_to_bigquery(df_final)
        print(f"✓ Total rows processed: {len(df_final)}")
    else:
        print("\n✗ No data to insert.")


if __name__ == "__main__":
    main()