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
API_URL = "https://open.dianplus.cn:443/api/vpc/rs/isv/sku/getSku"
OUTPUT_DIR = Path(
    "/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/"
    "My Drive/03. CODE & DOCUMENTS/data_export_csv"
)

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
    Load product data from Dianplus API.
    
    Returns:
        DataFrame containing product data
    """
    headers = {
        "Token": TOKEN
    }
    
    all_rows = []
    page_num = 1
    page_size = 100
    
    print(f"Fetching product data from Dianplus API...")
    
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
    
    # Flatten nested JSON structure using the flatten_data function
    df = flatten_data(all_rows)

    # Rename and reorder columns to match COLUMN_RENAME_MAP
    df = rename_and_reorder_columns(df)
   
    df = convert_booleans_to_binary(df)
    
    print(f"Total product records fetched: {len(df)}")
    return df

def flatten_data(product_raw):
    """Flatten product data while preserving all fields. Extracts first element from skuPropValList array."""
    
    # Just normalize the product data with all nested objects flattened
    df = pd.json_normalize(product_raw, sep=".", errors="ignore")
    
    # If skuPropValList exists as an array, flatten the first element
    if 'skuPropValList' in df.columns:
        skuPropValList_df = df['skuPropValList'].apply(
            lambda x: x[0] if isinstance(x, list) and len(x) > 0 else {}
        ).apply(pd.Series)
        # Add prefix to columns
        skuPropValList_df.columns = ['skuPropValList.' + str(col) for col in skuPropValList_df.columns]
        # Join with main dataframe and drop original column
        df = pd.concat([df, skuPropValList_df], axis=1)
        df = df.drop(columns=['skuPropValList'])
    
    print(f"\nData Structure:")
    print(f"  Products from API: {len(product_raw)}")
    print(f"  Rows in DataFrame: {len(df)}")
    print(f"  Total columns: {len(df.columns)}")
    
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

def convert_booleans_to_binary(df):
    """
    Convert boolean columns to binary (0/1) values.
    Columns with boolean values that already have 'is_' prefix keep their names.
    """
    # Work with a copy to avoid modifying during iteration
    df_copy = df.copy()
    
    # Only process columns that actually contain True/False values
    for col in df.columns:
        # Check for boolean dtype or string representations of booleans
        if df[col].dtype == bool:
            # Direct boolean column
            df_copy[col] = df[col].astype(int)
        else:
            # Check string representations (case-insensitive)
            str_vals = df[col].astype(str)
            # Check for both 'True'/'False' (Python default) and 'true'/'false' (JSON)
            is_bool_col = str_vals.isin(['True', 'False', 'true', 'false', 'TRUE', 'FALSE']).any()
            
            if is_bool_col:
                # Convert to binary
                df_copy[col] = str_vals.str.lower().map({'true': 1, 'false': 0})
    
    return df_copy


def main():
    """
    Main function to fetch product data and save to CSV.
    """
    # Fetch product data
    df_final = load_data()
    
    # Save to CSV
    if not df_final.empty:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = OUTPUT_DIR / f"dianplus_product_{timestamp}.csv"
        
        df_final.to_csv(output_file, index=False, encoding='utf-8-sig')
        print(f"\n✓ Data saved to: {output_file}")
        print(f"✓ Total records: {len(df_final)}")
    else:
        print("\n✗ No data to save.")


if __name__ == "__main__":
    main()