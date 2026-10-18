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
ADVERTISER_ID = "7161770060200050689"
API_URL = "https://business-api.tiktok.com/open_api/v1.3/adgroup/get/"
OUTPUT_DIR = Path(
    "/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/"
    "My Drive/03. CODE & DOCUMENTS/data_export_csv"
)

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
        "campaign_automation_type": "campaign_automation_type",
        "adgroup_id": "adgroup_id",
        "adgroup_name": "adgroup_name",
        "age_groups": "age_groups",
        "operation_status": "operation_status",
        "secondary_status": "secondary_status",
        "schedule_start_time": "schedule_start_time",
        "schedule_end_time": "schedule_end_time",
        "schedule_type": "schedule_type",
        "frequency_schedule": "frequency_schedule",
        "scheduled_budget": "scheduled_budget",
        "budget_mode": "budget_mode",
        "budget": "budget",
        "placement_type": "placement_type",   
        "promotion_type": "promotion_type",
        "gender": "gender",
        "optimization_goal": "optimization_goal",
        "optimization_event": "optimization_event",
        "is_smart_performance_campaign": "is_smart_performance_campaign",
        "included_custom_actions": "included_custom_actions",
        "product_source": "product_source",
        "actions": "actions",
        "smart_interest_behavior_enabled": "smart_interest_behavior_enabled",
        "location_ids": "location_ids",
        "view_attribution_window": "view_attribution_window",
        "deep_bid_type": "deep_bid_type",
        "operating_systems": "operating_systems",
        "skip_learning_phase": "skip_learning_phase",
        "keywords": "keywords",
        "frequency": "frequency",
        "placements": "placements",
        "spending_power": "spending_power",
        "billing_event": "billing_event",
        "interest_category_ids": "interest_category_ids",
        "bid_display_mode": "bid_display_mode",
        "audience_ids": "audience_ids",
        "languages": "languages", 
        "tiktok_subplacements": "tiktok_subplacements",
        "modify_time": "modify_time"
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
UTC_TO_VIETNAM_COLS = ["create_time", "modify_time","schedule_start_time","schedule_end_time"]


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

    # Remove '[]' values in all columns
    df = df.astype(str).replace(['nan', '{}','[]','None','UNSET'], '')

    # Reorder columns and rename using COLUMN_RENAME_MAP
    ordered_cols = [c for c in COLUMN_RENAME_MAP if c in df.columns]
    df = df[ordered_cols].rename(columns=COLUMN_RENAME_MAP)

    return df



def export_data(df, output_file):
    """Export DataFrame to CSV with UTF-8 BOM for Excel compatibility."""
    df.to_csv(output_file, index=False, encoding="utf-8-sig", na_rep="", quoting=1)


def main():
    parser = argparse.ArgumentParser(description="Export TikTok Ads data to BigQuery.")
    parser.add_argument("--start-date", default=None,
                        help="Start date in Vietnam time: YYYY-MM-DDTHH:MM:SS (e.g. 2026-01-01T00:00:00)")
    parser.add_argument("--end-date", default=None,
                        help="End date in Vietnam time: YYYY-MM-DDTHH:MM:SS (e.g. 2026-04-09T23:59:59)")
    parser.add_argument("--output", default=None, help="Custom output CSV filename")
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

     # --- Export CSV ---
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    now_ts = datetime.now().strftime("%Y%m%d%H%M%S")
    filename = args.output or f"tiktok_ads_report_{now_ts}.csv"
    output_file = OUTPUT_DIR / filename

    export_data(df, str(output_file))
    print(f"  ✓ Exported {df.shape[0]} rows × {df.shape[1]} columns to {output_file}")


if __name__ == "__main__":
    main()