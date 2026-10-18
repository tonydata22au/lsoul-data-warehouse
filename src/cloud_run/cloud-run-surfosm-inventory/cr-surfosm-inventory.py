#!/usr/bin/env python3
"""
Surfosm inventory export — Google Cloud Function HTTP handler.
Fetches inventory data from the Surfosm API and inserts it into BigQuery.

Routes:
    GET /healthz
        Health check — returns 200 OK.
    GET /run
        Yesterday's orders (Vietnam time), default behaviour.
    GET /run?start_date=2026-05-01T00:00:00&end_date=2026-05-09T23:59:59
        Date range in Vietnam time (UTC+7) — converted to UTC for the API.
    GET /run?all=1
        All orders with no date filter (use with caution).

Deploy (Cloud Functions Gen2):
    gcloud functions deploy surfosm-inventory --gen2 --runtime python311 --region asia-southeast1 --source versions/cloud-run-surfosm-inventory --entry-point export_inventory --trigger-http --no-allow-unauthenticated --set-env-vars SURFOSM_API_KEY=YOUR_API_KEY
    gcloud run deploy surfosm-inventory --source versions/cloud-run-surfosm-inventory --region asia-southeast1 --project marine-cycle-484213-b4 --allow-unauthenticated --quiet 
"""

import argparse
import json
import logging
import os
import warnings
from datetime import datetime, timedelta

import pandas as pd
import requests
from google.cloud import bigquery
from pandas import json_normalize
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings("ignore", category=pd.errors.PerformanceWarning)
logging.basicConfig(level=logging.INFO)

# API Configuration
API_KEY = os.environ["SURFOSM_API_KEY"]
API_URL = "https://api-app.scaleup-fulfilment.com/openapi/inventory"

# BigQuery configuration
BQ_DATASET = os.getenv("BQ_DATASET", "surfosm")
BQ_TABLE = os.getenv("BQ_TABLE", "raw_surfosm_inventory")

COLUMN_RENAME_MAP = {
    "as_of_date": "as_of_date",
    "sku": "sku",
    "barcode": "barcode",
    "product_name": "product_name",
    "warehouse_name": "warehouse_name",
    "warehouse_code": "warehouse_code",
    "stock.on_hand": "stock_on_hand",
    "stock.normal": "stock_normal",
    "stock.defect": "stock_defect",
    "stock.quarantine": "stock_quarantine",
    "stock.expired": "stock_expired",
    "stock.shelf_life_hold": "stock_shelf_life_hold",
    "stock.pending_destruction": "stock_pending_destruction",
    "updated_at": "updated_at",
}


def fetch_inventory(date=None):
    """Fetch all inventory items for a specific date (or no date filter)."""
    headers = {"x-api-key": API_KEY}
    all_items = []
    page_num = 1
    page_size = 1000

    while True:
        params = {"page": page_num, "per_page": page_size}
        if date:
            params["date"] = date

        try:
            response = requests.get(API_URL, params=params, headers=headers, timeout=120)
            response.raise_for_status()
            payload = response.json()
        except requests.exceptions.RequestException as e:
            raise ValueError(f"API request failed: {e}")
        except Exception as e:
            raise ValueError(f"Failed to parse API response: {e}")

        data = payload.get("data", {})
        response_as_of_date = data.get("as_of_date", "")
        items = data.get("items", [])
        if not items:
            break

        # Ensure each item carries the response-level as_of_date.
        for item in items:
            if isinstance(item, dict) and "as_of_date" not in item:
                item["as_of_date"] = response_as_of_date

        all_items.extend(items)

        total_pages = data.get("total_pages", 1)
        total = data.get("total", 0)
        logging.info(
            "Fetched page %s/%s: %s items (total so far: %s of %s)",
            page_num,
            total_pages,
            len(items),
            len(all_items),
            total,
        )

        has_next_page = data.get("has_next_page", False)
        if not has_next_page or page_num >= total_pages:
            break

        page_num += 1

    return all_items


def flatten_data(raw_items):
    """Explode warehouses array; one row per SKU x warehouse."""
    if not raw_items:
        return pd.DataFrame()

    df = json_normalize(
        raw_items,
        record_path=["warehouses"],
        meta=["as_of_date", "sku", "barcode", "product_name"],
        errors="ignore",
    )

    # Flatten nested stock object if present.
    if "stock" in df.columns and df["stock"].apply(lambda x: isinstance(x, dict)).any():
        stock_df = pd.json_normalize(
            df["stock"].apply(lambda x: x if isinstance(x, dict) else {}).tolist()
        )
        stock_df.columns = ["stock." + col for col in stock_df.columns]
        stock_df.index = df.index
        df = pd.concat([df.drop(columns=["stock"]), stock_df], axis=1)

    return df.copy()


def rename_and_reorder_columns(df):
    """Select and reorder columns based on COLUMN_RENAME_MAP."""
    new_df_dict = {}
    for original_col, new_col in COLUMN_RENAME_MAP.items():
        if original_col in df.columns:
            new_df_dict[new_col] = df[original_col]
        else:
            new_df_dict[new_col] = pd.Series([""] * len(df), index=df.index)

    result_df = pd.DataFrame(new_df_dict)

    if "updated_at" in result_df.columns:
        def _fmt_updated_at(val):
            if not val or val == "" or pd.isna(val):
                return ""
            try:
                clean = str(val).replace("Z", "").split("+")[0].split(".")[0]
                return datetime.strptime(clean, "%Y-%m-%dT%H:%M:%S").strftime("%Y%m%d%H%M%S")
            except (ValueError, AttributeError):
                return val

        result_df["updated_at"] = result_df["updated_at"].apply(_fmt_updated_at)

    return result_df


def insert_to_bigquery(df, project_id=None, dataset_id=BQ_DATASET, table_id=BQ_TABLE):
    """Insert DataFrame into BigQuery."""
    for col in df.columns:
        df[col] = df[col].apply(lambda x: str(x) if x is not None else None)

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
        return load_job.output_rows
    finally:
        client.close()


def _parse_date_input(value):
    """Parse date strings from query params and return a date object."""
    if value is None:
        return None

    cleaned = str(value).strip()
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(cleaned, fmt).date()
        except ValueError:
            continue

    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00")).date()
    except ValueError as e:
        raise ValueError(
            f"Invalid date '{value}'. Use YYYY-MM-DD or ISO datetime like YYYY-MM-DDTHH:MM:SS"
        ) from e


def build_dates_to_fetch(start_date=None, end_date=None, date=None):
    """Resolve date inputs into a list of YYYY-MM-DD strings."""
    if start_date and end_date:
        start = _parse_date_input(start_date)
        end = _parse_date_input(end_date)
        if start > end:
            raise ValueError("start_date must be before or equal to end_date")

        dates = []
        current = start
        while current <= end:
            dates.append(current.isoformat())
            current += timedelta(days=1)
        return dates

    if date:
        parsed = _parse_date_input(date)
        return [parsed.isoformat()]

    return [(datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")]


def run_export(project_id=None, start_date=None, end_date=None, date=None, dry_run=False):
    """Run export flow used by Cloud Function and optional CLI."""
    dates_to_fetch = build_dates_to_fetch(start_date=start_date, end_date=end_date, date=date)

    all_frames = []
    for each_date in dates_to_fetch:
        logging.info("Fetching inventory for date: %s", each_date)
        raw_items = fetch_inventory(date=each_date)
        if not raw_items:
            logging.info("No inventory items found for %s, skipping.", each_date)
            continue

        df = flatten_data(raw_items)
        if df.empty:
            logging.info("No rows after flattening for %s, skipping.", each_date)
            continue

        df = rename_and_reorder_columns(df)
        final_columns = list(COLUMN_RENAME_MAP.values())
        df = df.reindex(columns=final_columns, fill_value="")
        all_frames.append(df)

    if not all_frames:
        return {"ok": True, "message": "No data to insert.", "rows": 0}, 200

    combined_df = pd.concat(all_frames, ignore_index=True)

    if dry_run:
        return {
            "ok": True,
            "message": "Dry run completed.",
            "rows": int(len(combined_df)),
            "dates": dates_to_fetch,
        }, 200

    inserted_rows = insert_to_bigquery(combined_df, project_id=project_id)
    return {
        "ok": True,
        "message": "Export completed.",
        "rows": int(inserted_rows),
        "dates": dates_to_fetch,
    }, 200


def export_inventory(request):
    """Google Cloud Function HTTP entrypoint."""
    json_headers = {"Content-Type": "application/json"}

    path = (request.path or "") if request is not None else ""
    if request.method == "GET" and path.endswith("/healthz"):
        return json.dumps({"ok": True, "service": "surfosm-inventory"}), 200, json_headers

    args = request.args or {}
    start_date = args.get("start_date")
    end_date = args.get("end_date")
    date = args.get("date")
    dry_run = str(args.get("dry_run", "0")).lower() in {"1", "true", "yes"}

    try:
        project_id = os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
        payload, status = run_export(
            project_id=project_id,
            start_date=start_date,
            end_date=end_date,
            date=date,
            dry_run=dry_run,
        )
        return json.dumps(payload), status, json_headers
    except ValueError as e:
        return json.dumps({"ok": False, "error": str(e)}), 400, json_headers
    except Exception as e:
        logging.exception("Export failed")
        return json.dumps({"ok": False, "error": str(e)}), 500, json_headers


def main():
    """Optional CLI mode for local/manual execution."""
    parser = argparse.ArgumentParser(description="Export Surfosm inventory data to BigQuery")
    parser.add_argument("--date", default=None, help="Single date in format YYYY-MM-DD")
    parser.add_argument("--start_date", default=None, help="Start date in format YYYY-MM-DD")
    parser.add_argument("--end_date", default=None, help="End date in format YYYY-MM-DD")
    parser.add_argument("--dry_run", action="store_true", help="Run without inserting to BigQuery")
    parser.add_argument("--project_id", default=None, help="GCP project ID override")
    args = parser.parse_args()

    payload, status = run_export(
        project_id=args.project_id,
        start_date=args.start_date,
        end_date=args.end_date,
        date=args.date,
        dry_run=args.dry_run,
    )
    print(payload)
    raise SystemExit(0 if status == 200 else 1)


if __name__ == "__main__":
    main()
