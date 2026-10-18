import argparse
import hashlib
import logging
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
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Disable SSL warnings for development/testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logging.basicConfig(level=logging.INFO)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

# API Configuration
MERCHANT_CODE = "13939"
APP_KEY = os.environ["DIANPLUS_APP_KEY"]
APP_SECRET = os.environ["DIANPLUS_APP_SECRET"]
VERSION = "1.0"
AUTH_URL = "https://open.dianplus.cn/api/product/rs/isv/auth/get_token"
API_URL = "https://open.dianplus.cn:443/api/vpc/rs/isv/sku/getSku"

# Global variable to cache the token
_cached_token = None
_token_expiry = None



COLUMN_RENAME_MAP = {

                "brandId": "brandId",
                "childBrandId": "childBrandId",
                #"childBrandOutId": "childBrandOutId",
                "childBrandCode": "childBrandCode",
                "childBrandName": "childBrandName",
                "skuId": "skuId",
                "spuId": "spuId",
                "status": "status",
                "lastModifyTime": "lastModifyTime",
                "spuMerchantCode": "spuMerchantCode",
                #"spuOfficialInfo": "spuOfficialInfo",
                "merchantCode": "merchantCode",
                #"spuStandardCode": "spuStandardCode",
                "standardCode": "standardCode",
                #"extMerchantCode": "extMerchantCode",
                #"extSkuCode": "extSkuCode",
                #"spuTitle": "spuTitle",
                "title": "title",
                #"mainPicUrl": "mainPicUrl",
                #"downloadPic": "downloadPic",
                #"prodType": "prodType",
                "catId": "catId",
                #"catOutId": "catOutId",
                "catCode": "catCode",
                        "skuPropValList.propCode": "skuPropValList_propCode",
                        "skuPropValList.groupName": "skuPropValList_groupName",
                        #"skuPropValList.propName": "skuPropValList_propName",
                        "skuPropValList.valCode": "skuPropValList_valCode",
                        "skuPropValList.valName": "skuPropValList_valName",
                        "skuPropValList.valSort": "skuPropValList_valSort",
                        #"skuPropValList.position": "skuPropValList_position",
                        #"skuPropValList.lastModifyTime": "skuPropValList_lastModifyTime",
                #"skuPropValJson": "skuPropValJson",
                "topCatName": "topCatName",
                #"specGroupName": "specGroupName",
                #"specTempId": "specTempId",
                #"gradeId": "gradeId",
                #"gradeName": "gradeName",
                "colorPropName": "colorPropName",
                "colorCode": "colorCode",
                "colorName": "colorName",
                "colorGroup": "colorGroup",
                "colorSort": "colorSort",
                "sizePropName": "sizePropName",
                "sizeCode": "sizeCode",
                "sizeName": "sizeName",
                # "sizeGroup": "sizeGroup",
                "sizeSort": "sizeSort",
                "suggestPrice": "suggestPrice",
                "marketPrice": "marketPrice",
                "salePrice": "salePrice",
                "costPrice": "costPrice",
                # "purchasePrice": "purchasePrice",
                "year": "year",
                # "season": "season",
                # "ranges": "ranges",
                # "series": "series",
                # "pattern": "pattern",
                # "sex": "sex",
                # "productCatCode": "productCatCode",
                # "supplierCode": "supplierCode",
                # "supplierName": "supplierName",
                # "tags": "tags",
                # "tagCover": "tagCover",
                # "filter": "filter",
                # "marketTime": "marketTime",
                # "delistTime": "delistTime",
                # "style": "style",
                # "section": "section",
                "bigCat": "bigCat",
                # "middleCat": "middleCat",
                # "smallCat": "smallCat",
                "execStandard": "execStandard",
                "securityType": "securityType",
                "mainFabric": "mainFabric",
                # "fabricType": "fabricType",
                # "soldAmount": "soldAmount",
                # "weight": "weight",
                # "length": "length",
                # "width": "width",
                # "height": "height",
                # "remark": "remark",
                # "remark1": "remark1",
                # "remark2": "remark2",
                # "remark3": "remark3",
                # "colorPropSign": "colorPropSign",
                # "colorPropVals": "colorPropVals",
                # "sizePropSign": "sizePropSign",
                # "sizePropVals": "sizePropVals",
                "multiTopCat": "is_multiTopCat",
                "oneTimesTitle": "is_oneTimesTitle",
                "oneTimesSgtPrice": "is_oneTimesSgtPrice",
                "oneTimesSalPrice": "is_oneTimesSalPrice",
                # "customPropertyValues": "customPropertyValues",
                # "customProp1": "customProp1",
                # "customProp2": "customProp2",
                # "customProp3": "customProp3",
                # "customProp4": "customProp4",
                # "customProp5": "customProp5",
                # "customProp6": "customProp6",
                # "customProp7": "customProp7",
                # "customProp8": "customProp8",
                # "customProp9": "customProp9",
                # "customProp10": "customProp10",
                # "customProp11": "customProp11",
                # "customProp12": "customProp12",
                # "customProp13": "customProp13",
                # "customProp14": "customProp14",
                # "customProp15": "customProp15",
                # "customProp16": "customProp16",
                # "customProp17": "customProp17",
                # "customProp18": "customProp18",
                # "customProp19": "customProp19",
                # "customProp20": "customProp20",
                # "ext0": "ext0",
                # "ext1": "ext1",
                # "ext2": "ext2",
                # "ext3": "ext3",
                # "ext4": "ext4",
                # "ext5": "ext5",
                # "ext6": "ext6",
                # "ext7": "ext7",
                # "ext8": "ext8",
                # "ext9": "ext9",
                # "ext10": "ext10",
                # "unionCodes": "unionCodes",
                # "b2b": "b2b",
                # "sourceSpuCode": "sourceSpuCode",
                # "sourceSpuId": "sourceSpuId",
                # "customPrice1": "customPrice1",
                # "customPrice2": "customPrice2",
                # "customPrice3": "customPrice3",
                # "customPrice4": "customPrice4",
                # "customPrice5": "customPrice5",
                # "customPrice6": "customPrice6",
                # "customPrice7": "customPrice7",
                # "customPrice8": "customPrice8",
                # "customPrice9": "customPrice9",
                # "customPrice10": "customPrice10",
                # "customPrice11": "customPrice11",
                # "customPrice12": "customPrice12",
                # "customPrice13": "customPrice13",
                # "customPrice14": "customPrice14",
                # "customPrice15": "customPrice15",
                # "customPrice16": "customPrice16",
                # "customPrice17": "customPrice17",
                # "customPrice18": "customPrice18",
                # "customPrice19": "customPrice19",
                # "customPrice20": "customPrice20",
                # "designerId": "designerId",
                # "designerCode": "designerCode",
                # "designerDesc": "designerDesc",
                # "profileId": "profileId",
                # "profileValue": "profileValue",
                # "forceUnicode": "forceUnicode",
                # "spuExtSyncField": "spuExtSyncField"       
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

def load_data():
    """
    Load inventory data from Dianplus API.
    
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
    page_size = 100
    
    print(f"Fetching inventory data from Dianplus API...")
    
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

    df = convert_datetime_format(df)
    
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

def convert_datetime_format(df):
    """
    Convert datetime columns from Shanghai timezone to Vietnam timezone,
    then format from 'YYYY-MM-DD HH:MM:SS' to 'YYYYMMDDHHMMSS'.
    
    Args:
        df: DataFrame with datetime columns in Shanghai timezone
    
    Returns:
        DataFrame with converted datetime columns in Vietnam timezone
    """
    datetime_columns = ['lastModifyTime']
    shanghai_tz = pytz.timezone('Asia/Shanghai')
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    
    for col in datetime_columns:
        if col in df.columns:
            # Parse datetime and localize to Shanghai timezone
            df[col] = pd.to_datetime(df[col], errors='coerce')
            # Localize to Shanghai timezone and convert to Vietnam timezone
            df[col] = df[col].dt.tz_localize(shanghai_tz).dt.tz_convert(vietnam_tz)
            # Format as YYYYMMDDHHMMSS, but keep NaT as None
            df[col] = df[col].apply(lambda x: x.strftime('%Y%m%d%H%M%S') if pd.notna(x) else None)
    
    return df

def clean_nulls_for_bigquery(df):
    """
    Clean DataFrame by converting None, NaN, empty strings, and 'None' strings to proper NULL values.
    
    Args:
        df: DataFrame to clean
    
    Returns:
        DataFrame with cleaned null values
    """
    # Replace various forms of null/empty values with None
    df = df.replace({
        '': None,
        'None': None,
        'nan': None,
        'NaN': None,
        'null': None,
        'NULL': None,
    })
    
    # Replace pandas NaN with None
    df = df.where(pd.notna(df), None)
    
    return df

def insert_to_bigquery(df, project_id=None, dataset_id="dianplus", table_id="raw_dianplus_product"):
    """Insert DataFrame into BigQuery."""
    # Clean null values first
    df = clean_nulls_for_bigquery(df)
    
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


def run_export(*, project_id=None, start_date=None, end_date=None, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
    # Load data from Dianplus API
    df_final = load_data()
    
    # Check if we have data
    if df_final.empty:
        print("0 entries found. No data to export.")
        return "No data found", 200
    
    if dry_run:
        print("Dry run: skipping BigQuery load")
        return "Dry run: skipped load", 200
    
    insert_to_bigquery(df_final, project_id=project_id)
    return "Success", 200


app = Flask(__name__)


@app.route("/")
def run():
    logging.info("Triggering Dianplus inventory data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500


def main():
    parser = argparse.ArgumentParser(description="Export Dianplus inventory data to BigQuery.")
    parser.add_argument("--project-id", default=None, help="GCP project ID")
    parser.add_argument("--dry-run", action="store_true", help="Skip BigQuery load")
    args = parser.parse_args()

    message, _ = run_export(
        project_id=args.project_id,
        dry_run=args.dry_run,
    )
    print(message)


if __name__ == "__main__":
    main()
