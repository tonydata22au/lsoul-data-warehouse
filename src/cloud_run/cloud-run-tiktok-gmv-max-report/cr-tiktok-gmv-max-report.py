#!/usr/bin/env python3
"""
Script to load TikTok GMV Max data from TikTok API, flatten nested structures, and export to BigQuery.
Runs as a Flask HTTP service (Cloud Run) or as a CLI tool.
Default: Get yesterday's GMV Max data from T00:00:00 to T23:59:59 in Vietnam time (UTC+7).

Usage (CLI):
    gcloud run deploy tiktok-gmv-max-report --source versions/cloud-run-tiktok-gmv-max-report --region asia-southeast1 --project marine-cycle-484213-b4 --no-allow-unauthenticated --quiet

Usage (Cloud Run HTTP):
    GET /    # Triggers yesterday's export
"""
import argparse
import logging
import time
import warnings
from datetime import datetime, timedelta

import pandas as pd
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

ACCESS_TOKEN = os.environ["TIKTOK_VN_ACCESS_TOKEN"]
ADVERTISER_ID = "7161770060200050689"
STORE_IDS = ["7494709656316250791"]
API_URL = "https://business-api.tiktok.com/open_api/v1.3/gmv_max/report/get/"

DIMENSIONS = ["campaign_id","stat_time_day"]

# Ordered mapping: API column name -> output column name.
# The dict order defines the fixed column order in the CSV.
COLUMN_RENAME_MAP = {
    # --- Dimensions ---
    "stat_time_day":                                 "stat_time_day",
    "campaign_id":                                   "campaign_id",
    # --- Cost & Delivery ---
    "campaign_name": "campaign_name",
    "operation_status": "operation_status",
    "schedule_end_time": "schedule_end_time",
    "schedule_start_time": "schedule_start_time",
    "schedule_type": "schedule_type",
    "cost": "cost",
    "cost_per_order": "cost_per_order",
    "cost_per_10_second_live_view": "cost_per_10_second_live_view",
    "cost_per_live_view": "cost_per_live_view",
    "gross_revenue": "gross_revenue",
    "net_cost": "net_cost",
    "target_roi_budget": "target_roi_budget",
    "roi": "roi",
    "orders": "orders",
    "roas_bid": "roas_bid",
    "max_delivery_budget": "max_delivery_budget",
    #"tt_account_profile_image_url": "tt_account_profile_image_url"
    "10_second_live_views": "10_second_live_views",
    "bid_type": "bid_type",
    "identity_id": "identity_id",
    "live_follows": "live_follows",
    "live_views": "live_views",
    "tt_account_name": "tt_account_name"
}

# Derive METRICS list from the map (excluding dimensions)
METRICS = [m for m in COLUMN_RENAME_MAP if m not in DIMENSIONS]


def load_data(start_date, end_date):
    """
    Load data from TikTok Reporting API with pagination.

    Args:
        start_date: Start date in format 'YYYY-MM-DD'.
        end_date:   End date in format 'YYYY-MM-DD'.

    Returns:
        list[dict]: Raw rows from the API.
    """
    headers = {
        "Access-Token": ACCESS_TOKEN,
    }
    all_rows = []
    page = 1
    page_size = 1000

    print("Fetching data from TikTok Reporting API...")
    print(f"  Start date: {start_date}")
    print(f"  End date:   {end_date}")

    while True:
        params = {
            "advertiser_id": ADVERTISER_ID,
            "store_ids": json.dumps(STORE_IDS),
            "start_date": start_date,
            "end_date": end_date,
            "dimensions": json.dumps(DIMENSIONS),
            "metrics": json.dumps(METRICS),
            "page": page,
            "page_size": page_size,
        }

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


def process_data(raw_rows):
    """
    Flatten API rows into a flat DataFrame.
    Each row has 'dimensions' and 'metrics' dicts — merge them into one flat dict.
    """
    flat = []
    for row in raw_rows:
        record = {}
        record.update(row.get("dimensions", {}))
        record.update(row.get("metrics", {}))
        flat.append(record)

    df = pd.DataFrame(flat)

    if "stat_time_day" in df.columns:
        df["stat_time_day"] = pd.to_datetime(df["stat_time_day"]).dt.strftime("%Y-%m-%d")

    if "country_code" in df.columns:
        df = df[df["country_code"].notna() & (df["country_code"] != "None")]

    # Reorder columns and rename using COLUMN_RENAME_MAP
    ordered_cols = [c for c in COLUMN_RENAME_MAP if c in df.columns]
    df = df[ordered_cols].rename(columns=COLUMN_RENAME_MAP)

    return df

def insert_to_bigquery(df, project_id=None, dataset_id="raw_tiktok", table_id="raw_tiktok_gmv_max_report"):
    """Insert DataFrame into BigQuery."""
    # Convert all columns to string to match BQ schema
    df = df.astype(str)
   
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
    vietnam_tz = pytz.timezone('Asia/Ho_Chi_Minh')
    now_vn = datetime.now(vietnam_tz)
    yesterday = now_vn - timedelta(days=1)

    start_date = start_date or yesterday.strftime("%Y-%m-%d")
    end_date = end_date or yesterday.strftime("%Y-%m-%d")

    # Fetch data in 30-day chunks
    start_dt = datetime.strptime(start_date, "%Y-%m-%d").date()
    end_dt = datetime.strptime(end_date, "%Y-%m-%d").date()
    max_days = 30
    raw_rows = []

    chunk_start = start_dt
    while chunk_start <= end_dt:
        chunk_end = min(chunk_start + timedelta(days=max_days - 1), end_dt)
        print(f"\n--- Chunk: {chunk_start} to {chunk_end} ---")
        rows = load_data(
            start_date=chunk_start.strftime("%Y-%m-%d"),
            end_date=chunk_end.strftime("%Y-%m-%d"),
        )
        raw_rows.extend(rows)
        chunk_start = chunk_end + timedelta(days=1)

    if not raw_rows:
        print("0 entries found. No data to export.")
        return "0 entries found", 200

    df = process_data(raw_rows)
    print(f"  Processed {df.shape[0]} rows x {df.shape[1]} columns")

    if dry_run:
        print("Dry run: skipping BigQuery load")
        return "Dry run: skipped load", 200

    insert_to_bigquery(df, project_id=project_id)
    return "Success", 200


app = Flask(__name__)


@app.route("/")
def run():
    logging.info("Triggering TikTok GMV Max data export (HTTP)...")
    try:
        message, status = run_export()
        return message, status
    except Exception as exc:
        logging.exception("Export failed")
        return f"Error: {exc}", 500


def main():
    parser = argparse.ArgumentParser(description="Export TikTok GMV Max data to BigQuery.")
    parser.add_argument("--start-date", default=None, help="Start date YYYY-MM-DD")
    parser.add_argument("--end-date", default=None, help="End date YYYY-MM-DD")
    parser.add_argument("--dry-run", action="store_true", help="Skip BigQuery load")
    args = parser.parse_args()

    message, _ = run_export(
        start_date=args.start_date,
        end_date=args.end_date,
        dry_run=args.dry_run,
    )
    print(message)


if __name__ == "__main__":
    main()
