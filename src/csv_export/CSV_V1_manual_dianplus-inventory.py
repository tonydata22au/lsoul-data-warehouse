#!/usr/bin/env python3
import json
import warnings
import pytz
import requests
import hashlib
from datetime import datetime
import pandas as pd
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

TOKEN = os.environ["DIANPLUS_TOKEN"]
MERCHANT_CODE = "13939"
APP_KEY = os.environ["DIANPLUS_APP_KEY"]
APP_SECRET = os.environ["DIANPLUS_APP_SECRET"]
VERSION = "1.0"
API_URL = "https://open.dianplus.cn:443/api/vpc/rs/isv/inventory/getInvs"
OUTPUT_DIR = Path(
    "/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/"
    "My Drive/03. CODE & DOCUMENTS/data_export_csv"
)

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
    headers = {
        "Token": TOKEN
    }
    
    all_rows = []
    page_num = 1
    page_size = 2000
    
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


def main():
    """
    Main function to fetch inventory data and save to CSV.
    """
    # Fetch inventory data
    df_final = load_data()
    
    # Save to CSV
    if not df_final.empty:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = OUTPUT_DIR / f"dianplus_inventory_{timestamp}.csv"
        
        df_final.to_csv(output_file, index=False, encoding='utf-8-sig')
        print(f"\n✓ Data saved to: {output_file}")
        print(f"✓ Total records: {len(df_final)}")
    else:
        print("\n✗ No data to save.")


if __name__ == "__main__":
    main()