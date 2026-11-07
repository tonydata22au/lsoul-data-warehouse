#!/usr/bin/env python3
"""
Script to load inventory data from Jushuitan API, flatten nested structures, and export to BigQuery.
Runs as a Flask HTTP service (Cloud Run) or as a CLI tool.
Default: Get yesterday's inventory data from T00:00:00 to T23:59:59 in Shanghai time.

Recovered on 2026-11-07 from the live revision's source (Cloud Build of jushuitan-inventory-00001-v7l);
credentials now come from env vars (Secret Manager in Cloud Run) and the dataset from BQ_RAW_DATASET (default raw).
The service needs Direct VPC egress (--network=default --subnet=default --vpc-egress=all-traffic): Jushuitan
allowlists the Cloud NAT static IP below. Keep those flags on every deploy.

Usage (CLI — first-time deploy with static egress IP via Cloud NAT):
    gcloud run deploy jushuitan-inventory \

        --source cloud-run \
        --region asia-southeast1 \
        --project marine-cycle-484213-b4 \
        --no-allow-unauthenticated \
        --vpc-connector=jushuitan-connector \
        --vpc-egress=all-traffic \
        --quiet

    gcloud run deploy jushuitan-inventory --source cloud-run --region asia-southeast1 --project marine-cycle-484213-b4 --no-allow-unauthenticated --network=default --subnet=default --vpc-egress=all-traffic --quiet

    Note: --vpc-connector routes all outbound traffic through Cloud NAT static IP 35.213.148.171.
    Verify via: GET /healthz  (returns outbound IP in response)

Usage (Cloud Run HTTP):
    GET /healthz    # Returns current outbound IP (for verification)
    GET /           # Triggers yesterday's inventory export
"""

import argparse
import logging
import os
import sys
import json
import time
import warnings
import pytz
import requests
import hashlib
from datetime import datetime, timedelta
import pandas as pd
from pandas import json_normalize
from pathlib import Path
from flask import Flask
from google.cloud import bigquery
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

logging.basicConfig(level=logging.INFO)

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

EXPECTED_EGRESS_IP = "35.213.148.171"  # Cloud NAT static IP reserved for this service


def _get_outbound_ip() -> str:
    """Fetch the current outbound IP as seen by external services."""
    try:
        resp = requests.get("https://api.ipify.org", timeout=10)
        return resp.text.strip()
    except Exception as e:
        return f"unknown ({e})"

# API Configuration
APP_KEY = os.environ["JUSHUITAN_APP_KEY"]
APP_SECRET = os.environ["JUSHUITAN_APP_SECRET"]
VERSION = "2"
CHARSET = "utf-8"
AUTH_URL = "https://openapi.jushuitan.com/openWeb/auth/getInitToken"
API_URL = "https://openapi.jushuitan.com/open/inventory/query"


# Global variable to cache the token
_cached_token = None
_token_expiry = None


def _debug_print(debug, message):
    if debug:
        print(message)


COLUMN_RENAME_MAP = {
                "ts": "ts",
                "modified": "modified",
                "i_id": "item_id",
                "sku_id": "sku_id",
                "name": "name",
                "qty": "qty",
                "in_qty": "in_qty",
                "return_qty": "return_qty",
                "order_lock": "order_lock",
                "pick_lock": "pick_lock",
                "defective_qty": "defective_qty",
                "purchase_qty": "purchase_qty",
                "min_qty": "min_qty",
                "max_qty": "max_qty",
                "allocate_qty": "allocate_qty",
                "virtual_qty": "virtual_qty",
                
}

def calculate_sign_for_auth_access_token(timestamp, debug=False):
    """
    Calculate MD5 sign for the auth token endpoint.
    Parameters are concatenated in alphabetical order: app_secret,app_key,charset,code,grant_type,timestamp

    Args:
        timestamp: Unix timestamp string — must be the SAME value used in the request params.

    Returns:
        MD5 hash (lowercase, 32-bit)
    """
    # Construct the raw string with parameters in alphabetical order
    raw = (
        f"{APP_SECRET}"
        f"app_key{APP_KEY}"
        f"charset{CHARSET}"
        f"code{'696969'}"
        f"grant_type{'authorization_code'}"
        f"timestamp{timestamp}"
    )
    
    _debug_print(debug, f"Raw string before MD5 encryption: {raw}")
    
    # Calculate MD5 hash
    sign = hashlib.md5(raw.encode('utf-8')).hexdigest()
    _debug_print(debug, f"Sign after MD5 encryption: {sign}")
    return sign

def get_auth_access_token(debug=False):
    """
    Get authentication token from Jushuitan API.
    Caches the token to avoid unnecessary API calls.
    
    Returns:
        Token string from the API response
        
    Raises:
        Exception if authentication fails
    """
    global _cached_token, _token_expiry
    
    # Check if we have a cached token that hasn't expired
    # Assuming token is valid for at least 1 hour, refresh if less than 5 minutes left
    if _cached_token and _token_expiry and datetime.now() < _token_expiry:
        print(f"Using cached authentication token")
        return _cached_token
    
    print("Fetching new authentication token...")

    # Generate timestamp once — shared between sign calculation and request params
    timestamp = str(int(datetime.now().timestamp()))
    sign = calculate_sign_for_auth_access_token(timestamp, debug=debug)

    params = {
        "app_key": APP_KEY,
        "charset": CHARSET,
        "timestamp": timestamp,
        "grant_type": "authorization_code",
        "code": "696969",
        "sign": sign,
    }
    
    try:
        response = requests.post(AUTH_URL, data=params, timeout=69)
        
        if response.status_code != 200:
            raise Exception(f"Authentication failed with status code: {response.status_code}")
        
        data = response.json()
        
        if data.get("code") != 0:
            error_msg = data.get('msg') or 'Unknown authentication error'
            raise Exception(f"Authentication API error: {error_msg}")
        
        token = data.get("data", {}).get("access_token")
        
        if not token:
            raise Exception("No token received from authentication API")
        
        # Cache the token (set expiry to 55 minutes from now to be safe)
        _cached_token = token
        _token_expiry = datetime.now() + timedelta(seconds=data.get("data", {}).get("expires_in", 3600))
        print(f"✓ Successfully obtained authentication token")
        return token
        
    except requests.exceptions.RequestException as e:
        raise Exception(f"Authentication request failed: {e}")

def calculate_sign_for_api(access_token, biz_json, timestamp, debug=False):
    """
    Calculate MD5 sign for the inventory data endpoint.
    Parameters are concatenated in alphabetical order: app_secret,access_token,app_key,biz,charset,timestamp,version

    Args:
        access_token: token from get_auth_access_token()
        biz_json: JSON string of the biz dict — must be the SAME value sent in the request params.
        timestamp: Unix timestamp string — must be the SAME value used in the request params.

    Returns:
        MD5 hash (lowercase, 32-bit)
    """
    # Construct the raw string with parameters in alphabetical order
    raw = (
        f"{APP_SECRET}"
        f"access_token{access_token}"
        f"app_key{APP_KEY}"
        f"biz{biz_json}"
        f"charset{CHARSET}"
        f"timestamp{timestamp}"
        f"version{VERSION}"
    )
    
    _debug_print(debug, f"Raw string before MD5 encryption: {raw}")
    
    # Calculate MD5 hash
    sign = hashlib.md5(raw.encode('utf-8')).hexdigest()
    _debug_print(debug, f"Sign after MD5 encryption: {sign}")
    return sign

def _fetch_pages(token, headers, modified_begin=None, modified_end=None, debug=False):
    """
    Fetch all paginated order data for a single date window.

    Args:
        token: API access token
        headers: HTTP request headers
        modified_begin: window start string in format "YYYY-MM-DD HH:MM:SS"; omit for --ALL mode
        modified_end:   window end   string in format "YYYY-MM-DD HH:MM:SS"; omit for --ALL mode

    Returns:
        List of raw order dicts from the API
    """
    all_rows = []
    page_num = 1
    page_size = 100
    max_retries = 3
    retry_delay = 5  # seconds between retries

    if modified_begin and modified_end:
        print(f"  Fetching [{modified_begin}] → [{modified_end}] ...")
    else:
        print(f"  Fetching ALL inventory rows (no date filter) ...")

    while True:
        page_success = False
        api_error = False
        inventory_rows = []

        for attempt in range(1, max_retries + 1):
            # Regenerate timestamp and sign on every attempt — timestamp must match sign
            time_stamp = str(int(datetime.now().timestamp()))
            print(f"  Page {page_num}, attempt {attempt}/{max_retries} — timestamp: {time_stamp}")

            biz_dict = {
                "ts": 1,
                "is_get_total": True,
                "page_index": page_num,
                "page_size": page_size
            }
            if modified_begin and modified_end:
                biz_dict["modified_begin"] = modified_begin
                biz_dict["modified_end"]   = modified_end
            biz_json = json.dumps(biz_dict, separators=(',', ':'), ensure_ascii=False)
            sign = calculate_sign_for_api(token, biz_json, time_stamp, debug=debug)

            params = {
                "app_key": APP_KEY,
                "access_token": token,
                "biz": biz_json,
                "charset": CHARSET,
                "timestamp": time_stamp,
                "version": VERSION,
                "sign": sign
            }

            try:
                if debug:
                    masked_params = dict(params)
                    if masked_params.get("access_token"):
                        masked_params["access_token"] = "***masked***"
                    if masked_params.get("sign"):
                        masked_params["sign"] = "***masked***"
                    print(f"  Request params: {json.dumps(masked_params, indent=2, ensure_ascii=False)}")
                response = requests.post(API_URL, headers=headers, data=params, timeout=69)
                print(f"  Response status code: {response.status_code}")

                if response.status_code != 200:
                    print(f"  HTTP error {response.status_code}: {response.text}")
                    if attempt < max_retries:
                        print(f"  Retrying in {retry_delay}s...")
                        time.sleep(retry_delay)
                    continue

                data = response.json()

                if data.get("code") != 0:
                    # API-level errors (bad params, auth) are not retryable
                    error_msg = data.get('msg') or 'Unknown error'
                    print(f"  API error: {error_msg}")
                    page_success = False
                    api_error = True
                    break

                # Inventory endpoint returns rows under "inventorys".
                # Keep a fallback to "orders" for compatibility with older payload handling.
                data_payload = data.get("data", {})
                if not isinstance(data_payload, dict):
                    data_payload = {}

                inventory_rows = data_payload.get("inventorys", [])
                if not inventory_rows:
                    inventory_rows = data_payload.get("orders", [])

                if not inventory_rows:
                    print(f"  No more data to fetch on page {page_num}.")
                    page_success = True
                    break

                all_rows.extend(inventory_rows)
                print(f"  Fetched page {page_num} with {len(inventory_rows)} inventory rows. Total so far: {len(all_rows)}")
                page_success = True
                break

            except requests.exceptions.RequestException as e:
                print(f"  Connection error on attempt {attempt}/{max_retries}: {e}")
                if attempt < max_retries:
                    wait = retry_delay * attempt  # 5s, 10s, 15s
                    print(f"  Retrying in {wait}s...")
                    time.sleep(wait)

        if api_error:
            # Same rule as jushuitan-order (decision D7, 2026-11-06): a non-zero API code ends the fetch and keeps
            # the pages so far
            print(f"  API error on page {page_num}. Stopping with {len(all_rows)} rows fetched so far.")
            break

        if not page_success:
            print(f"  Failed to fetch page {page_num} after {max_retries} attempts. Stopping.")
            # Fail the run: returning the pages so far would load a partial window as a success
            raise RuntimeError(f"Jushuitan page {page_num} failed after {max_retries} attempts")

        if not inventory_rows:
            break

        if len(inventory_rows) < page_size:
            print(f"  Received {len(inventory_rows)} rows (< page_size={page_size}) — no more pages.")
            break

        page_num += 1
        time.sleep(1)  # 1-second pause between pages to avoid rate limiting

    return all_rows


def load_data(start_date_input=None, end_date_input=None, fetch_all=False, debug=False):
    """
    Load all inventory data from the API.

    - Normal mode: accepts dates in ISO format (YYYY-MM-DDTHH:MM:SS), converts
      them to the API format (YYYY-MM-DD HH:MM:SS), and chunks requests into
      7-day windows when the range exceeds 7 days.
        - fetch_all mode: omits modified_begin / modified_end entirely and retrieves
            all inventory rows in the account (use with --ALL flag).

    Args:
        start_date_input: start date string, e.g. "2026-05-01T00:00:00"
        end_date_input:   end   date string, e.g. "2026-05-09T23:59:59"
        fetch_all:        when True, ignore date params and fetch everything

    Returns:
        DataFrame containing inventory data
    """
    # Get authentication token once for all chunks
    token = get_auth_access_token(debug=debug)
    headers = {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"
    }

    all_rows = []

    if fetch_all:
        print("\n--ALL flag set: fetching all inventory rows with no date filter.")
        all_rows = _fetch_pages(token, headers, debug=debug)
    else:
        # Parse and validate input dates
        try:
            start_dt = datetime.strptime(start_date_input.strip(), "%Y-%m-%dT%H:%M:%S")
            end_dt   = datetime.strptime(end_date_input.strip(),   "%Y-%m-%dT%H:%M:%S")
        except ValueError:
            raise ValueError(
                "Dates must be in format YYYY-MM-DDTHH:MM:SS — e.g. 2026-05-07T00:00:00"
            )

        if end_dt <= start_dt:
            raise ValueError("end_date must be later than start_date")

        # Build 7-day chunks over the full range
        chunks = []
        chunk_start = start_dt
        while chunk_start < end_dt:
            chunk_end = min(chunk_start + timedelta(days=7), end_dt)
            chunks.append((
                chunk_start.strftime("%Y-%m-%d %H:%M:%S"),
                chunk_end.strftime("%Y-%m-%d %H:%M:%S")
            ))
            chunk_start = chunk_end

        total_chunks = len(chunks)
        print(f"\nDate range: {start_dt} → {end_dt}")
        if total_chunks > 1:
            print(f"Range exceeds 7 days — splitting into {total_chunks} chunks.")
        else:
            print(f"Date range fits within 7 days — single chunk.")

        for i, (chunk_begin, chunk_end) in enumerate(chunks, start=1):
            print(f"\nChunk {i}/{total_chunks}: {chunk_begin} → {chunk_end}")
            chunk_rows = _fetch_pages(token, headers, chunk_begin, chunk_end)
            all_rows.extend(chunk_rows)
            print(f"Chunk {i} complete — {len(chunk_rows)} orders fetched.")

    if not all_rows:
        print("No data fetched.")
        return pd.DataFrame()

    # Flatten API rows to DataFrame before applying column mapping
    df = json_normalize(all_rows, sep=".", errors="ignore")

    # Rename and reorder columns to match COLUMN_RENAME_MAP
    df = rename_and_reorder_columns(df)

    print(f"\nTotal inventory rows fetched: {len(df)}")
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
    Format datetime columns from 'YYYY-MM-DD HH:MM:SS' to 'YYYYMMDDHHMMSS' (no timezone conversion).
    Also adds 'vn_modified' column converted from Shanghai to Vietnam timezone.

    Args:
        df: DataFrame with datetime columns in Shanghai timezone

    Returns:
        DataFrame with formatted datetime columns and new vn_modified column
    """
    datetime_columns = ['modified']
    shanghai_tz = pytz.timezone('Asia/Shanghai')
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')

    for col in datetime_columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors='coerce')
            df[col] = df[col].dt.strftime('%Y%m%d%H%M%S')

    # Add vn_modified by converting modified from Shanghai to Vietnam timezone
    if 'modified' in df.columns:
        vn_modified = pd.to_datetime(df['modified'], format='%Y%m%d%H%M%S', errors='coerce')
        vn_modified = vn_modified.dt.tz_localize(shanghai_tz).dt.tz_convert(vietnam_tz)
        df.insert(df.columns.get_loc('modified') + 1, 'vn_modified', vn_modified.dt.strftime('%Y%m%d%H%M%S'))

    return df


def clean_nulls_for_bigquery(df):
    """Clean DataFrame by converting None, NaN, empty strings, and 'None' strings to proper NULL values."""
    df = df.replace({
        '': None,
        'None': None,
        'nan': None,
        'NaN': None,
        'null': None,
        'NULL': None,
    })
    df = df.where(pd.notna(df), None)
    return df



def insert_to_bigquery(df, project_id=None, dataset_id=os.getenv("BQ_RAW_DATASET", "raw"), table_id="raw_jushuitan_inventory"):
    """Insert DataFrame into BigQuery."""
    df = clean_nulls_for_bigquery(df)

    # Convert all columns to string, preserving None values
    for col in df.columns:
        df[col] = df[col].apply(lambda x: str(x) if x is not None else None)

    client = bigquery.Client(project=project_id)
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
        print(f"  ✓ Successfully loaded {load_job.output_rows} rows into {dataset_id}.{table_id} [{load_job.job_id}]")
    finally:
        client.close()


def run_export(*, project_id=None, start_date=None, end_date=None, fetch_all=False, dry_run=False):
    """Run export flow used by both CLI and HTTP handler."""
    outbound_ip = _get_outbound_ip()
    if outbound_ip == EXPECTED_EGRESS_IP:
        print(f"✓ Outbound IP: {outbound_ip} (matches Cloud NAT static IP)")
    else:
        print(f"⚠ Outbound IP: {outbound_ip} (expected: {EXPECTED_EGRESS_IP})")

    if fetch_all:
        print("Mode: fetch_all (no date filter — fetching all orders)")
        df_final = load_data(fetch_all=True)
    else:
        yesterday = datetime.now() - timedelta(days=1)
        start_date_input = start_date or yesterday.strftime("%Y-%m-%dT00:00:00")
        end_date_input   = end_date   or yesterday.strftime("%Y-%m-%dT23:59:59")
        df_final = load_data(start_date_input, end_date_input)

    if df_final.empty:
        print("0 entries found. No data to export.")
        return "No data found", 200

    df_final = convert_datetime_format(df_final)
    print(f"  Processed {df_final.shape[0]} rows x {df_final.shape[1]} columns")

    if dry_run:
        print("Dry run: skipping BigQuery load")
        return "Dry run: skipped load", 200

    insert_to_bigquery(df_final, project_id=project_id)
    return "Success", 200


app = Flask(__name__)


@app.before_request
def _log_ip_once():
    """Log outbound IP on the first request to confirm Cloud NAT routing."""
    if not getattr(app, '_ip_logged', False):
        outbound_ip = _get_outbound_ip()
        if outbound_ip == EXPECTED_EGRESS_IP:
            logging.info(f"✓ Outbound IP confirmed: {outbound_ip} (matches Cloud NAT static IP)")
        else:
            logging.warning(f"⚠ Outbound IP is {outbound_ip} — expected {EXPECTED_EGRESS_IP}. Check VPC connector config.")
        app._ip_logged = True


@app.route("/healthz")
def healthz():
    """Health check endpoint — returns current outbound IP for verification."""
    outbound_ip = _get_outbound_ip()
    status = "OK" if outbound_ip == EXPECTED_EGRESS_IP else "WARN"
    msg = f"{status} | outbound_ip={outbound_ip} | expected={EXPECTED_EGRESS_IP}"
    logging.info(msg)
    return msg, 200


@app.route("/")
def run():
    logging.info("Triggering Jushuitan order data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500


def main():
    parser = argparse.ArgumentParser(description="Export Jushuitan order data to BigQuery.")
    parser.add_argument("--start-date", default=None, help="Start date YYYY-MM-DDTHH:MM:SS (Shanghai timezone)")
    parser.add_argument("--end-date",   default=None, help="End date YYYY-MM-DDTHH:MM:SS (Shanghai timezone)")
    parser.add_argument("--project-id", default=None, help="GCP project ID")
    parser.add_argument("--all",        dest="fetch_all", action="store_true", help="Fetch all orders with no date filter")
    parser.add_argument("--dry-run",    action="store_true", help="Skip BigQuery load")
    parser.add_argument("--serve",      action="store_true", help="Start Flask HTTP server (local Cloud Run simulation)")
    args = parser.parse_args()

    if args.serve:
        port = int(os.environ.get("PORT", 8080))
        logging.info(f"Starting Flask server on 0.0.0.0:{port}")
        app.run(host="0.0.0.0", port=port, debug=False)
    else:
        message, _ = run_export(
            project_id=args.project_id,
            start_date=args.start_date,
            end_date=args.end_date,
            fetch_all=args.fetch_all,
            dry_run=args.dry_run,
        )
        print(message)


if __name__ == "__main__":
    main()