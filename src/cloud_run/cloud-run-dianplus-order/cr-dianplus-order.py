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
API_URL = "https://open.dianplus.cn:443/api/vpc/rs/isv/order/getOrder"

# Global variable to cache the token
_cached_token = None
_token_expiry = None



COLUMN_RENAME_MAP = {

                "brandId": "brandId",
                "orderId": "orderId",
                "createTime": "createTime",
                "lastModifyTime": "lastModifyTime",
                "payTime": "payTime",
                #"sourceOrderId": null,
                #"origOrderId": null,
                "orderType": "orderType",
                "orderStatus": "orderStatus",
                "payStatus": "payStatus",
                "source": "source",
                "srcSystem": "srcSystem",
                #"hasBarter": 0,
                #"takeOwn": 1,
                "customId": "customId",
                "customShopId": "customShopId",
                "exclusiveGuideId": "exclusiveGuideId",
                "customShopCode": "customShopCode",
                #"customDjId": null,
                "customLevelId": "customLevelId",
                "vipId": "vipId",
                "vipNum": "vipNum",
                "vipMobilePhone": "vipMobilePhone",
                #"name": "name",
                #"mobilePhone": "mobilePhone",
                "provinceCode": "provinceCode",
                "provinceName": "provinceName",
                "cityCode": "cityCode",
                "cityName": "cityName",
                "areaCode": "areaCode",
                "areaName": "areaName",
                #"address": "address",
                "sumAmount": "sumAmount",
                "sumSuggestPrice": "sumSuggestPrice",
                "sumSalePrice": "sumSalePrice",
                "sumDealPrice": "sumDealPrice",
                #"sumMallPrice": "sumMallPrice",
                "brandDiscount": "brandDiscount",
                "couponDiscount": "couponDiscount",
                "moLingDiscount": "moLingDiscount",
                "customDiscount": "customDiscount",
                "integralDiscount": "integralDiscount",
                #"storeCardPrice": "storeCardPrice",
                #"payedPoints": "payedPoints",
                #"backPoints": "backPoints",
                #"saleChannelId": "saleChannelId",
                "saleChannelDjId": "saleChannelDjId",
                "saleChannelCode": "saleChannelCode",
                "saleShopId": "saleShopId",
                "saleShopDjId": "saleShopDjId",
                "saleShopCode": "saleShopCode",
                #"executeShopId": "executeShopId",
                #"executeShopDjId": "executeShopDjId",
                #"executeShopCode": "executeShopCode",
                #"saleStaffId": "saleStaffId",
                "saleStaffDjId": "saleStaffDjId",
                #"saleStaffCode": "saleStaffCode",
                #"carryFee": "carryFee",
                #"cusCouponId": "cusCouponId",
                #"deliveryCarryFee": "deliveryCarryFee",
                #"createStaffId": "createStaffId",
                "createStaffDjId": "createStaffDjId",
                #"createStaffErpId": "createStaffErpId",
                "createStaffCode": "createStaffCode",
                #"createStaffName": "createStaffName",
                #"sellerMark": "sellerMark",
                #"buyerMark": "buyerMark",
                #"thirdShopName": "thirdShopName",
                #"distributorName": "distributorName",
                #"couponCodes": "couponCodes",
                        "orderItems.orderItemId": "orderItems_orderItemId",
                        "orderItems.orderId": "orderItems_orderId",
                        #"orderItems.spuId": "orderItems_spuId",
                        "orderItems.spuDjId": "orderItems_spuDjId",
                        "orderItems.spuCode": "orderItems_spuCode",
                        #"orderItems.skuId": "orderItems_skuId",
                        "orderItems.skuDjId": "orderItems_skuDjId",
                        "orderItems.skuCode": "orderItems_skuCode",
                        "orderItems.skuName": "orderItems_skuName",
                        "orderItems.colorCode": "orderItems_colorCode",
                        "orderItems.colorName": "orderItems_colorName",
                        "orderItems.sizeCode": "orderItems_sizeCode",
                        "orderItems.sizeName": "orderItems_sizeName",
                        "orderItems.amount": "orderItems_amount",
                        "orderItems.suggestPrice": "orderItems_suggestPrice",
                        "orderItems.salePrice": "orderItems_salePrice",
                        "orderItems.dealPrice": "orderItems_dealPrice",
                        "orderItems.sumSuggestPrice": "orderItems_sumSuggestPrice",
                        "orderItems.sumSalePrice": "orderItems_sumSalePrice",
                        "orderItems.sumDealPrice": "orderItems_sumDealPrice",
                        #"orderItems.saleStaffId": "orderItems_saleStaffId",
                        "orderItems.saleStaffDjId": "orderItems_saleStaffDjId",
                        "orderItems.saleStaffCode": "orderItems_saleStaffCode",
                        #"orderItems.skuLacks": "orderItems_skuLacks",
                        #"orderItems.activitys": "orderItems_activitys",
                        #"orderItems.remark": "orderItems_remark",
                        #"orderItems.prodType": "orderItems_prodType",
                        #"orderItems.cashCouponDiscount": "orderItems_cashCouponDiscount",
                        #"orderItems.totalCashCouponDiscount": "orderItems_totalCashCouponDiscount",
                        #"orderItems.unUsedCashCouponDiscount": "orderItems_unUsedCashCouponDiscount",
                        #"orderItems.totalUnUsedCashCouponDiscount": "orderItems_totalUnUsedCashCouponDiscount",
                        #"orderItems.orderDiscountDtos": "orderItems_orderDiscountDtos",
                        #"orderItems.uniqueCodes": "orderItems_uniqueCodes",
                        "orderItems.payInfo": "orderItems_payInfo",
                                "orderItems.itemPayInfos.payMethodCode": "orderItems_itemPayInfos_payMethodCode",
                                "orderItems.itemPayInfos.payMethodDesc": "orderItems_itemPayInfos_payMethodDesc",
                                "orderItems.itemPayInfos.custPayMethodCode": "orderItems_itemPayInfos_custPayMethodCode",
                                "orderItems.itemPayInfos.custPayMethodName": "orderItems_itemPayInfos_custPayMethodName",
                                "orderItems.itemPayInfos.amt": "orderItems_itemPayInfos_amt",
                                "orderItems.itemPayInfos.totalAmt": "orderItems_itemPayInfos_totalAmt",
                                #"orderItems.itemPayInfos.principalAccPayAmt": "orderItems_itemPayInfos_principalAccPayAmt",
                                #"orderItems.itemPayInfos.totalPrincipalAccPayAmt": "orderItems_itemPayInfos_totalPrincipalAccPayAmt",
                                #"orderItems.itemPayInfos.giftAccPayAmt": "orderItems_itemPayInfos_giftAccPayAmt",
                                #"orderItems.itemPayInfos.totalGiftAccPayAmt": "orderItems_itemPayInfos_totalGiftAccPayAmt",
                                #"orderItems.itemPayInfos.giftCardInfos": "orderItems_itemPayInfos_giftCardInfos",
                                #"orderItems.itemPayInfos.amtCoupon": "orderItems_itemPayInfos_amtCoupon",
                                #"orderItems.itemPayInfos.totalAmtCoupon": "orderItems_itemPayInfos_totalAmtCoupon",
                                #"orderItems.itemPayInfos.amtSubsidy": "orderItems_itemPayInfos_amtSubsidy",
                                #"orderItems.itemPayInfos.totalAmtSubsidy": "orderItems_itemPayInfos_totalAmtSubsidy",
                                #"orderItems.itemPayInfos.thirdCouponInfos": "orderItems_itemPayInfos_thirdCouponInfos",
                                #"orderItems.itemPayInfos.payType": "orderItems_itemPayInfos_payType",
                                #"orderItems.itemPayInfos.firstMoney": "orderItems_itemPayInfos_firstMoney",
                "serviceGuides.staffName": "serviceGuides_staffName",
                "serviceGuides.proportion":"serviceGuides_proportion",
                "payInfos.payType": "payInfos_payType",
                "payInfos.payCode": "payInfos_payCode",
                "payInfos.outPayChannelDesc": "payInfos_outPayChannelDesc",
                "payInfos.amount": "payInfos_amount",
                "payInfos.otherAmount": "payInfos_otherAmount",
                #"payInfos.cardNum": "payInfos_cardNum",
                #"payInfos.cardId": "payInfos_cardId",
                #"payInfos.cardDesc": "payInfos_cardDesc",
                #"payInfos.outPayId": "payInfos_outPayId",
                #"payInfos.cashVoucherDtos": "payInfos_cashVoucherDtos"
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
    Convert date string in format 'YYYY-MM-DDTHH:MM:SS' (Vietnam timezone) to format 'YYYY-MM-DD HH:MM:SS'  Asia/shanghai timezone.
    
    Args:
        date_string: Date string in format '2024-01-01T00:00:00' in Vietnam time or None
        
    Returns:
        or 14 days ago if date_string is None or empty
    """
    if not date_string or date_string.strip() == "":
        return None
    
    try:
        # Parse as Vietnam time (UTC+7)
        vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        dt_vietnam = vietnam_tz.localize(dt)
        # Convert to Asia/Shanghai timezone (UTC+8)
        shanghai_tz = pytz.timezone('Asia/Shanghai')
        dt_shanghai = dt_vietnam.astimezone(shanghai_tz)
        return dt_shanghai.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS")

def load_data(start_time=None, end_time=None):
    """
    Load order data from Dianplus API for the given time range.
    
    Args:
        start_time: Start time in format 'YYYY-MM-DD HH:MM:SS'
        end_time: End time in format 'YYYY-MM-DD HH:MM:SS'
    
    Returns:
        DataFrame containing order data
    """
    # Get authentication token
    token = get_auth_token()
    
    headers = {
        "Token": token
    }
    
    all_rows = []
    page_num = 1
    page_size = 100
    
    print(f"Fetching data from Dianplus API from {start_time} to {end_time}...")
    
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
            "createTimeStart": start_time,
            "createTimeEnd": end_time,
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
            
            orders = data.get("resultObject", {}).get("results", [])
            
            if not orders:
                print(f"No more data to fetch on page {page_num}.")
                break
            
            all_rows.extend(orders)
            print(f"Fetched page {page_num} with {len(orders)} orders. Total so far: {len(all_rows)}")
            
            page_num += 1
            
        except requests.exceptions.RequestException as e:
            print(f"Request error: {e}")
            break
    
    if not all_rows:
        print("No data fetched.")
        return pd.DataFrame()
    
    # Flatten nested JSON structure using the flatten_data function
    df = flatten_data(all_rows)
    
    # Rename and reorder columns to match COLUMN_RENAME_MAP
    df = rename_and_reorder_columns(df)
    
    print(f"Total orders fetched: {len(df)}")
    return df

def flatten_data(orders_raw):
    """Flatten order data, expanding items into separate rows while preserving and normalizing all nested fields."""
    
    # Check if orders have items (array that needs to be exploded into rows)
    has_items = any(isinstance(o.get("orderItems"), list) and o.get("orderItems") for o in orders_raw)
    
    if has_items:
        # Normalize with items as record_path (each item becomes a row)
        # and include all order-level fields as meta
        df = json_normalize(
            orders_raw,
            record_path="orderItems",
            meta=[
                'brandId', 'orderId', 'createTime', 'lastModifyTime', 'payTime',
                'orderType', 'orderStatus', 'payStatus', 'source', 'srcSystem',
                'customId', 'customShopId', 'exclusiveGuideId', 'customShopCode',
                'customLevelId', 'vipId', 'vipNum', 'vipMobilePhone',
                'name', 'mobilePhone', 'provinceCode', 'provinceName',
                'cityCode', 'cityName', 'areaCode', 'areaName', 'address',
                'sumAmount', 'sumSuggestPrice', 'sumSalePrice', 'sumDealPrice', 'sumMallPrice',
                'brandDiscount', 'couponDiscount', 'moLingDiscount', 'customDiscount',
                'integralDiscount', 'storeCardPrice', 'payedPoints', 'backPoints',
                'saleChannelId', 'saleChannelDjId', 'saleChannelCode',
                'saleShopId', 'saleShopDjId', 'saleShopCode',
                'executeShopId', 'executeShopDjId', 'executeShopCode',
                'saleStaffId', 'saleStaffDjId', 'saleStaffCode',
                'carryFee', 'cusCouponId', 'deliveryCarryFee',
                'createStaffId', 'createStaffDjId', 'createStaffErpId',
                'createStaffCode', 'createStaffName',
                'sellerMark', 'buyerMark', 'thirdShopName', 'distributorName', 'couponCodes',
                'serviceGuides', 'payInfos',
            ],
            record_prefix="orderItems.",
            meta_prefix="",
            sep=".",
            errors="ignore"
        )
        
        # Flatten nested arrays within the data
        # 1. Flatten itemPayInfos array (within each orderItem) - take first element if array
        if 'orderItems.itemPayInfos' in df.columns:
            itemPayInfos_df = df['orderItems.itemPayInfos'].apply(
                lambda x: x[0] if isinstance(x, list) and len(x) > 0 else {}
            ).apply(pd.Series)
            # Add prefix to columns
            itemPayInfos_df.columns = ['orderItems.itemPayInfos.' + str(col) for col in itemPayInfos_df.columns]
            # Join with main dataframe and drop original column
            df = pd.concat([df, itemPayInfos_df], axis=1)
            df = df.drop(columns=['orderItems.itemPayInfos'])
        
        # 2. Flatten serviceGuides array (at order level) - take first element if array
        if 'serviceGuides' in df.columns:
            serviceGuides_df = df['serviceGuides'].apply(
                lambda x: x[0] if isinstance(x, list) and len(x) > 0 else {}
            ).apply(pd.Series)
            # Add prefix to columns
            serviceGuides_df.columns = ['serviceGuides.' + str(col) for col in serviceGuides_df.columns]
            # Join with main dataframe and drop original column
            df = pd.concat([df, serviceGuides_df], axis=1)
            df = df.drop(columns=['serviceGuides'])
        
        # 3. Flatten payInfos array (at order level) - take first element if array
        if 'payInfos' in df.columns:
            payInfos_df = df['payInfos'].apply(
                lambda x: x[0] if isinstance(x, list) and len(x) > 0 else {}
            ).apply(pd.Series)
            # Add prefix to columns
            payInfos_df.columns = ['payInfos.' + str(col) for col in payInfos_df.columns]
            # Join with main dataframe and drop original column
            df = pd.concat([df, payInfos_df], axis=1)
            df = df.drop(columns=['payInfos'])
        
        print(f"\nData Structure:")
        print(f"  Orders from API: {len(orders_raw)}")
        print(f"  Order items (rows): {len(df)}")
        print(f"  Note: Each order item creates a separate row in the table")
        print(f"  Item-level columns: {len([c for c in df.columns if c.startswith('orderItems.')])}")
        print(f"  Order-level columns: {len([c for c in df.columns if not c.startswith('orderItems.')])}")
    else:
        # No items, just normalize the order data with all nested objects flattened
        df = json_normalize(orders_raw, sep=".", errors="ignore")
        
        print(f"\nData Structure:")
        print(f"  Orders from API: {len(orders_raw)}")
        print(f"  Rows to insert: {len(df)}")
    
    return df.copy()

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

def chunk_date_range(start_date, end_date, chunk_days=15):
    """
    Split a date range into chunks of specified days.
    
    Args:
        start_date: Start datetime object
        end_date: End datetime object
        chunk_days: Number of days per chunk (default 15)
    
    Yields:
        Tuple of (chunk_start, chunk_end) datetime objects
    """
    current_start = start_date
    
    while current_start < end_date:
        current_end = min(current_start + timedelta(days=chunk_days), end_date)
        yield current_start, current_end
        current_start = current_end


def convert_datetime_format(df):
    """
    Convert datetime columns from Shanghai timezone to Vietnam timezone,
    then format from 'YYYY-MM-DD HH:MM:SS' to 'YYYYMMDDHHMMSS'.
    
    Args:
        df: DataFrame with datetime columns in Shanghai timezone
    
    Returns:
        DataFrame with converted datetime columns in Vietnam timezone
    """
    datetime_columns = ['createTime', 'lastModifyTime', 'payTime']
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

def insert_to_bigquery(df, project_id=None, dataset_id="dianplus", table_id="raw_dianplus_order"):
    """Insert DataFrame into BigQuery."""
    # Clean null values first
    df = clean_nulls_for_bigquery(df)
    
     # Convert all columns to string, preserving None; guard against list/dict cells where pd.isna returns an array
    def _coerce(x):
        if x is None:
            return None
        if isinstance(x, (list, dict)):
            return str(x)
        try:
            if pd.isna(x):
                return None
        except (TypeError, ValueError):
            pass
        return str(x)

    for col in df.columns:
        df[col] = df[col].apply(_coerce)
   
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
    # Set default dates if not provided
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    shanghai_tz = pytz.timezone('Asia/Shanghai')
    
    if end_date:
        end_date_vn_str = parse_date_to_unix(end_date)
    else:
        # Default: yesterday in Vietnam timezone
        end_date_vn = datetime.now(vietnam_tz) - timedelta(days=1)
        end_date_vn = end_date_vn.replace(hour=23, minute=59, second=59)
        end_date_sh = end_date_vn.astimezone(shanghai_tz)
        end_date_vn_str = end_date_sh.strftime("%Y-%m-%d %H:%M:%S")
    
    if start_date:
        start_date_vn_str = parse_date_to_unix(start_date)
    else:
        # Default: yesterday at 00:00:00 in Vietnam timezone
        if end_date:
            dt = datetime.strptime(end_date, "%Y-%m-%dT%H:%M:%S")
            dt_vietnam = vietnam_tz.localize(dt)
        else:
            dt_vietnam = datetime.now(vietnam_tz) - timedelta(days=1)
            dt_vietnam = dt_vietnam.replace(hour=23, minute=59, second=59)
        
        start_date_vn = dt_vietnam.replace(hour=0, minute=0, second=0)
        start_date_sh = start_date_vn.astimezone(shanghai_tz)
        start_date_vn_str = start_date_sh.strftime("%Y-%m-%d %H:%M:%S")
    
    # Parse the Shanghai timezone strings back to datetime objects for chunking
    start_dt = datetime.strptime(start_date_vn_str, "%Y-%m-%d %H:%M:%S")
    start_dt = shanghai_tz.localize(start_dt)
    end_dt = datetime.strptime(end_date_vn_str, "%Y-%m-%d %H:%M:%S")
    end_dt = shanghai_tz.localize(end_dt)
    
    # Calculate date difference
    date_diff = (end_dt - start_dt).days
    
    print(f"Date range: {start_date_vn_str} to {end_date_vn_str} ({date_diff} days)")
    
    all_data = []
    
    # If date range is more than 15 days, chunk it
    if date_diff > 15:
        print(f"Date range exceeds 15 days. Splitting into chunks...")
        for chunk_start, chunk_end in chunk_date_range(start_dt, end_dt, chunk_days=15):
            chunk_start_str = chunk_start.strftime("%Y-%m-%d %H:%M:%S")
            chunk_end_str = chunk_end.strftime("%Y-%m-%d %H:%M:%S")
            
            print(f"\n--- Fetching chunk: {chunk_start_str} to {chunk_end_str} ---")
            df_chunk = load_data(chunk_start_str, chunk_end_str)
            
            if not df_chunk.empty:
                all_data.append(df_chunk)
        
        if all_data:
            df_final = pd.concat(all_data, ignore_index=True)
        else:
            df_final = pd.DataFrame()
    else:
        df_final = load_data(start_date_vn_str, end_date_vn_str)
    
    # Check if we have data
    if df_final.empty:
        print("0 entries found. No data to export.")
        return "No data found", 200
    
    # Convert datetime format
    df_final = convert_datetime_format(df_final)
    print(f"  Processed {df_final.shape[0]} rows x {df_final.shape[1]} columns")
    
    if dry_run:
        print("Dry run: skipping BigQuery load")
        return "Dry run: skipped load", 200
    
    insert_to_bigquery(df_final, project_id=project_id)
    return "Success", 200


app = Flask(__name__)


@app.route("/")
def run():
    logging.info("Triggering Dianplus order data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500


def main():
    parser = argparse.ArgumentParser(description="Export Dianplus order data to BigQuery.")
    parser.add_argument("--start-date", default=None, help="Start date YYYY-MM-DDTHH:MM:SS (Vietnam timezone)")
    parser.add_argument("--end-date", default=None, help="End date YYYY-MM-DDTHH:MM:SS (Vietnam timezone)")
    parser.add_argument("--project-id", default=None, help="GCP project ID")
    parser.add_argument("--dry-run", action="store_true", help="Skip BigQuery load")
    args = parser.parse_args()

    message, _ = run_export(
        project_id=args.project_id,
        start_date=args.start_date,
        end_date=args.end_date,
        dry_run=args.dry_run,
    )
    print(message)


if __name__ == "__main__":
    main()
