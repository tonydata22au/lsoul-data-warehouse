#!/usr/bin/env python3
"""
Fetch Meta ads insights and load into BigQuery.
- Pulls ad-level insights with actions and cost_per_action_type.
- Flattens dynamic action fields (dots -> underscores) into columns.
- Loads into BigQuery using the same service-account flow as data_export_customer.py.

Usage:
    python3 src/local_run/meta_ads_a.py                            # Get yesterday's ad insights (date_preset=yesterday)
    python3 src/local_run/meta_ads_a.py --date-preset last_7d      # Use another Meta date_preset
    python3 src/local_run/meta_ads_a.py --all                      # Get all data (omit date_preset)
"""
import argparse
import json
import os
from datetime import datetime, date, timedelta
from pathlib import Path
from typing import Dict, List, Tuple

import pandas as pd
import requests
from google.cloud import bigquery
from google.cloud.exceptions import NotFound
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ACCESS_TOKEN = os.environ["META_ACCESS_TOKEN_LOCAL"]
AD_ACCOUNT_ID = "act_785254401088992"
API_VERSION = "v24.0"
BASE_HEADERS = [
    "date_start",
    "date_stop",
    "campaign_id",
    "campaign_name",
    "adset_name",
    "ad_name",
    "spend",
    "reach",
    "clicks",
    "cpc",
    "cpm",
]

# BigQuery config (borrowed from data_export_customer.py)
DATASET_ID = "raw_meta"
TABLE_ID = "raw_ads_reporting_a"
LOCATION = "asia-southeast1"

# BigQuery config — this script is expected to run from local-run/<folder>/,
# where credentials/google-credentials.json is a sibling of the script's parent.
BASE_DIR = Path(__file__).resolve().parent.parent.parent
SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sanitize_field(name: str) -> str:
    return name.replace(".", "_") if name else name


def sanitize_headers(headers: List[str]) -> List[str]:
    """Convert any header with dots to underscores to satisfy BigQuery naming."""
    return [sanitize_field(h) for h in headers]


def month_ranges_for_year(year: int) -> List[Tuple[str, str]]:
    """Return list of (since, until) date strings covering each month of the year up to today."""
    ranges: List[Tuple[str, str]] = []
    today = date.today()
    last_month = today.month if today.year == year else 12
    for month in range(1, last_month + 1):
        start = date(year, month, 1)
        if month == 12:
            end = date(year + 1, 1, 1) - timedelta(days=1)
        else:
            end = date(year, month + 1, 1) - timedelta(days=1)
        if end > today:
            end = today
        ranges.append((start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")))
    return ranges


def serialize(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=True)
    return value if value not in (None, "") else ""


def aggregate_action_values(items: list) -> Dict[str, float]:
    result: Dict[str, float] = {}
    if not isinstance(items, list):
        return result
    for entry in items:
        if not isinstance(entry, dict):
            continue
        action_type = entry.get("action_type")
        if not action_type:
            continue
        val = entry.get("value")
        if isinstance(val, str):
            try:
                val = float(val)
            except ValueError:
                pass
        if isinstance(val, (int, float)):
            result[action_type] = result.get(action_type, 0) + val
        elif val not in (None, ""):
            result[action_type] = val
    return result


def fetch_insights(params: Dict[str, str]) -> List[Dict]:
    url = f"https://graph.facebook.com/{API_VERSION}/{AD_ACCOUNT_ID}/insights"
    insights: List[Dict] = []
    next_url = url
    next_params = params.copy()

    while next_url:
        response = requests.get(next_url, params=next_params)
        if response.status_code != 200:
            raise ValueError(f"Meta API error {response.status_code}: {response.text}")
        data = response.json()
        insights.extend(data.get("data", []))
        paging = data.get("paging", {})
        next_url = paging.get("next")
        next_params = None  # paging.next already encodes params

    return insights


def build_dataframe(insights: List[Dict]) -> Tuple[pd.DataFrame, List[str], List[str]]:
    action_types = set()
    cpat_types = set()
    for item in insights:
        for entry in item.get("actions", []) or []:
            if isinstance(entry, dict) and entry.get("action_type"):
                action_types.add(entry["action_type"])
        for entry in item.get("cost_per_action_type", []) or []:
            if isinstance(entry, dict) and entry.get("action_type"):
                cpat_types.add(entry["action_type"])

    action_cols = [f"actions_{sanitize_field(t)}" for t in sorted(action_types)]
    cpat_cols = [f"cost_per_action_type_{sanitize_field(t)}" for t in sorted(cpat_types)]
    headers = sanitize_headers(BASE_HEADERS + action_cols + cpat_cols)

    rows = []
    for item in insights:
        actions_map_raw = aggregate_action_values(item.get("actions", []))
        cpat_map_raw = aggregate_action_values(item.get("cost_per_action_type", []))
        actions_map = {sanitize_field(k): v for k, v in actions_map_raw.items()}
        cpat_map = {sanitize_field(k): v for k, v in cpat_map_raw.items()}

        row = {
            "date_start": serialize(item.get("date_start", "")),
            "date_stop": serialize(item.get("date_stop", "")),
            "campaign_id": serialize(item.get("campaign_id", "")),
            "campaign_name": serialize(item.get("campaign_name", "")),
            "adset_name": serialize(item.get("adset_name", "")),
            "ad_name": serialize(item.get("ad_name", "")),
            "spend": serialize(item.get("spend", "")),
            "reach": serialize(item.get("reach", "")),
            "clicks": serialize(item.get("clicks", "")),
            "cpc": serialize(item.get("cpc", "")),
            "cpm": serialize(item.get("cpm", "")),
        }
        for col in action_cols:
            key = col.replace("actions_", "", 1)
            row[col] = serialize(actions_map.get(key, ""))
        for col in cpat_cols:
            key = col.replace("cost_per_action_type_", "", 1)
            row[col] = serialize(cpat_map.get(key, ""))
        rows.append(row)

    df = pd.DataFrame(rows, columns=headers)
    df.columns = sanitize_headers(list(df.columns))
    return df, action_cols, cpat_cols


def create_dataset_if_not_exists(client: bigquery.Client, dataset_id: str, location: str):
    dataset_ref = client.dataset(dataset_id)
    try:
        client.get_dataset(dataset_ref)
    except NotFound:
        ds = bigquery.Dataset(dataset_ref)
        ds.location = location
        client.create_dataset(ds)
    return dataset_ref


def load_to_bigquery(df: pd.DataFrame, project_id: str, dataset_id: str, table_id: str):
    client = bigquery.Client(project=project_id, credentials=credentials)
    try:
        dataset_ref = create_dataset_if_not_exists(client, dataset_id, LOCATION)
        table_ref = dataset_ref.table(table_id)

        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,
            ],
        )

        for col in df.columns:
            df[col] = df[col].astype(str).replace({"nan": "", "None": ""})

        load_job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
        load_job.result()
        print(f"✓ Loaded {load_job.output_rows} rows to {dataset_id}.{table_id} [{load_job.job_id}]")
    finally:
        client.close()


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Export Meta Ads Insights to BigQuery")
    parser.add_argument("--project-id", default=None, help="GCP project id; defaults to credential project")
    parser.add_argument("--dataset-id", default=DATASET_ID, help="BigQuery dataset id")
    parser.add_argument("--table-id", default=TABLE_ID, help="BigQuery table id")
    parser.add_argument("--date-preset", default="yesterday", help="Meta date_preset (e.g., yesterday, last_7d)")
    parser.add_argument("--all", action="store_true", help="Fetch all data (omit date_preset)")
    args = parser.parse_args()

    base_params = {
        "fields": "date_start,date_stop,campaign_id,campaign_name,adset_name,ad_name,spend,reach,clicks,cpc,cpm,actions,cost_per_action_type",
        "level": "ad",
        "time_increment": "1",
        "limit": "5000",
        "access_token": ACCESS_TOKEN,
    }

    insights: List[Dict] = []

    if not args.all and args.date_preset:
        if args.date_preset == "this_year":
            year = date.today().year
            print(f"Fetching insights month-by-month for {year}...")
            for since, until in month_ranges_for_year(year):
                params = base_params.copy()
                params["time_range"] = json.dumps({"since": since, "until": until})
                print(f"  Chunk {since} to {until}...")
                chunk = fetch_insights(params)
                insights.extend(chunk)
            print(f"Completed chunked fetch: {len(insights)} total records")
        else:
            params = base_params.copy()
            params["date_preset"] = args.date_preset
            print(f"Fetching insights with date_preset={args.date_preset}...")
            insights = fetch_insights(params)
    else:
        print("Fetching insights with no date_preset (beware of large ranges)...")
        insights = fetch_insights(base_params)

    if not insights:
        print("0 records returned; nothing to load.")
        return

    df, action_cols, cpat_cols = build_dataframe(insights)
    print(f"Fetched {len(df)} rows | actions: {len(action_cols)} cols | cost_per_action: {len(cpat_cols)} cols")

    load_to_bigquery(df, args.project_id or credentials.project_id, args.dataset_id, args.table_id)


if __name__ == "__main__":
    main()
