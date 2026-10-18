#!/usr/bin/env python3
"""
Script to load reporting basic auction campaign data from TikTok API, flatten nested structures, and prepare a DataFrame for export.
Default: Get yesterday's reporting basic auction campaign data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)

Usage:
    python3 local-run/tiktok_thai/tiktok_thai_data_export_campaign.py               # Get yesterday's reporting basic auction campaign data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7)
    python3 local-run/tiktok_thai/tiktok_thai_data_export_campaign.py --start-date 2025-05-01T00:00:00 --end-date 2026-09-04T23:59:59
    python3 local-run/tiktok_thai/tiktok_thai_data_export_campaign.py --All           # Get all reporting basic auction campaign data with no date filter (use with caution)
"""
import argparse
import json
import os
import time
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import pytz
import requests
from dotenv import load_dotenv
from google.cloud import bigquery
from google.oauth2 import service_account

# Load .env that sits next to this script
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")

ACCESS_TOKEN_FROM_ENV = os.environ.get("TIKTOK_ACCESS_TOKEN")
ADVERTISER_ID = "7412469132660228097"
API_URL = "https://business-api.tiktok.com/open_api/v1.3/campaign/get/"


# BigQuery config
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

# Ordered mapping: API column name -> output column name.
# The dict order defines the fixed column order in the CSV.
COLUMN_RENAME_MAP = {
    # --- Dimensions ---
    "create_time": "create_time",
    "advertiser_id": "advertiser_id",
    "campaign_id": "campaign_id",
    "campaign_name": "campaign_name",
    "operation_status": "operation_status",
    "secondary_status": "secondary_status",
    "budget": "budget",
    "budget_mode": "budget_mode",
    "campaign_type": "campaign_type",
    "campaign_automation_type": "campaign_automation_type",
    "objective": "objective",
    "objective_type": "objective_type",
    "is_search_campaign": "is_search_campaign",
    "is_new_structure": "is_new_structure",
    "is_smart_performance_campaign": "is_smart_performance_campaign",
    "modify_time": "modify_time",
}


def vietnam_to_utc(date_string):
    """
    Convert date string in Vietnam time (YYYY-MM-DDTHH:MM:SS) to UTC (YYYY-MM-DD HH:MM:SS).

    Args:
        date_string: e.g. '2026-01-01T00:00:00' in Vietnam time, or None.

    Returns:
        UTC string 'YYYY-MM-DD HH:MM:SS' or None.
    """
    if not date_string or date_string.strip() == "":
        return None

    try:
        vietnam_tz = pytz.timezone("Asia/Ho_Chi_Minh")
        dt = datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%S")
        dt_vietnam = vietnam_tz.localize(dt)
        dt_utc = dt_vietnam.astimezone(pytz.UTC)
        return dt_utc.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        raise ValueError(f"Invalid date format: {date_string}. Expected: YYYY-MM-DDTHH:MM:SS")


def load_data(start_date_utc=None, end_date_utc=None):
    """
    Load ad data from TikTok Ad Management API with pagination.

    Args:
        start_date_utc: Start date in UTC format 'YYYY-MM-DD HH:MM:SS', or None.
        end_date_utc:   End date in UTC format 'YYYY-MM-DD HH:MM:SS', or None.

    Returns:
        list[dict]: Raw ad rows from the API.
    """
    headers = {
        "Access-Token": ACCESS_TOKEN_FROM_ENV,
    }
    all_rows = []
    page = 1
    page_size = 1000

    print("Fetching data from TikTok Ad Management API...")
    if start_date_utc or end_date_utc:
        if start_date_utc:
            print(f"  Filtering start (UTC): {start_date_utc}")
        if end_date_utc:
            print(f"  Filtering end   (UTC): {end_date_utc}")
    else:
        print("  No date filters applied — fetching all ads")

    while True:
        params = {
            "advertiser_id": ADVERTISER_ID,
            "page": page,
            "page_size": page_size,
        }

        # Build filtering dict only when dates are provided
        filtering = {}
        if start_date_utc:
            filtering["creation_filter_start_time"] = start_date_utc
        if end_date_utc:
            filtering["creation_filter_end_time"] = end_date_utc
        if filtering:
            params["filtering"] = json.dumps(filtering)

        try:
            response = requests.get(API_URL, headers=headers, params=params, timeout=99999)
            response.raise_for_status()
            payload = response.json()
        except requests.RequestException as exc:
            print(f"  ✗ Request failed on page {page}: {exc}")
            break

        code = payload.get("code", -1)
        if code != 0:
            print(f"  ✗ API error (code={code}): {payload.get('message', 'unknown')}")
            break

        data = payload.get("data", {})
        rows = data.get("list", [])
        page_info = data.get("page_info", {})
        total_page = page_info.get("total_page", 1)
        total_number = page_info.get("total_number", 0)

        if not rows:
            break

        all_rows.extend(rows)
        print(f"  Page {page}/{total_page} — fetched {len(rows)} rows (total so far: {len(all_rows)}/{total_number})")

        if page >= total_page:
            break

        page += 1
        time.sleep(0.5)  # respect rate limits

    print(f"  Total rows fetched: {len(all_rows)}")
    return all_rows


# Columns to convert from UTC to Vietnam time (%Y%m%d%H%M%S)
UTC_TO_VIETNAM_COLS = ["create_time", "modify_time"]


def process_data(raw_rows):
    """Flatten API rows into a DataFrame and reorder/rename columns."""
    df = pd.DataFrame(raw_rows)

    # Convert UTC datetime columns to Vietnam time
    vietnam_tz = pytz.timezone("Asia/Ho_Chi_Minh")
    for col in UTC_TO_VIETNAM_COLS:
        if col in df.columns:
            df[col] = (
                pd.to_datetime(df[col], format="%Y-%m-%d %H:%M:%S", utc=True)
                .dt.tz_convert(vietnam_tz)
                .dt.strftime("%Y%m%d%H%M%S")
            )

    # Reorder columns and rename using COLUMN_RENAME_MAP
    ordered_cols = [c for c in COLUMN_RENAME_MAP if c in df.columns]
    df = df[ordered_cols].rename(columns=COLUMN_RENAME_MAP)

    return df


def insert_to_bigquery(df, project_id=None, dataset_id="raw_tiktok", table_id="raw_tiktok_thai_campaign"):
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
    parser = argparse.ArgumentParser(description="Export TikTok Campaign data to BigQuery.")
    parser.add_argument("--start-date", default=None,
                        help="Start date in Vietnam time: YYYY-MM-DDTHH:MM:SS (e.g. 2026-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None,
                        help="End date in Vietnam time: YYYY-MM-DDTHH:MM:SS (e.g. 2026-04-09T23:59:59)")
    parser.add_argument("--list", action="store_true", help="List columns and exit")
    args = parser.parse_args()

    # Convert Vietnam time inputs to UTC (None if not provided)
    start_date_utc = vietnam_to_utc(args.start_date) if args.start_date else None
    end_date_utc = vietnam_to_utc(args.end_date) if args.end_date else None

    if args.start_date:
        print(f"  Input start (Vietnam): {args.start_date} → UTC: {start_date_utc}")
    if args.end_date:
        print(f"  Input end   (Vietnam): {args.end_date} → UTC: {end_date_utc}")

    # --- Fetch data ---
    raw_rows = load_data(start_date_utc=start_date_utc, end_date_utc=end_date_utc)
    if not raw_rows:
        print("0 entries found. No data to export.")
        return

   # --- Process ---
    df = process_data(raw_rows)
    print(f"  Processed {df.shape[0]} rows × {df.shape[1]} columns")

    if args.list:
        print("\nColumns:")
        for col in df.columns:
            print(f"  - {col}")
        return

       # --- Insert to BigQuery ---
    insert_to_bigquery(df)


if __name__ == "__main__":
    main()