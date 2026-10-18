#!/usr/bin/env python3
"""
Magento order export — Google Cloud Run service.
Fetches orders from the Magento REST API and inserts them into BigQuery.

Routes:
    GET /healthz
        Health check — returns 200 OK.
    GET /run
        Yesterday's orders (Vietnam time), default behaviour.
    GET /run?start_date=2026-05-01T00:00:00&end_date=2026-05-09T23:59:59
        Date range in Vietnam time (UTC+7) — converted to UTC for the API.
    GET /run?all=1
        All orders with no date filter (use with caution).

Deploy:
    gcloud run deploy magento-order \
        --source cloud-run \
        --region asia-southeast1 \
        --project marine-cycle-484213-b4 \
        --no-allow-unauthenticated \
        --quiet
"""

import json
import logging
import os
import time
import warnings
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import pytz
import requests
from flask import Flask, jsonify, request
from google.cloud import bigquery
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
warnings.filterwarnings("ignore", category=pd.errors.PerformanceWarning)

app = Flask(__name__)

# ─── Magento API ──────────────────────────────────────────────────────────────
AUTH_URL  = "https://management.lsoul.com/rest/V1/integration/admin/token"
API_URL   = "https://management.lsoul.com/rest/V1/orders"
USERNAME  = os.environ["MAGENTO_USERNAME"]
PASSWORD  = os.environ["MAGENTO_PASSWORD"]
PAGE_SIZE = 1000

VN_TZ = pytz.timezone("Asia/Ho_Chi_Minh")

# ─── BigQuery ─────────────────────────────────────────────────────────────────
BQ_PROJECT = os.getenv("BQ_PROJECT", "marine-cycle-484213-b4")
BQ_DATASET = os.getenv("BQ_DATASET", "magento")
BQ_TABLE   = os.getenv("BQ_TABLE",   "raw_magento_order")

_BASE_DIR = Path(__file__).resolve().parent.parent
_SA_FILE  = _BASE_DIR / "credentials" / "google-credentials.json"
credentials = (
    service_account.Credentials.from_service_account_file(str(_SA_FILE))
    if _SA_FILE.exists()
    else None   # Application Default Credentials when running in Cloud Run
)

# ─── Token cache ──────────────────────────────────────────────────────────────
_cached_token = None
_token_expiry = None

# ─── Column mapping ───────────────────────────────────────────────────────────
COLUMN_RENAME_MAP = {
    # Order-level
    "created_at":                   "created_at",
    "updated_at":                   "updated_at",
    "increment_id":                 "increment_id",
    "entity_id":                    "entity_id",
    "order_currency_code":          "order_currency_code",
    "state":                        "state",
    "status":                       "status",
    "customer_email":               "customer_email",
    "customer_firstname":           "customer_firstname",
    "customer_lastname":            "customer_lastname",
    "customer_group_id":            "customer_group_id",
    "customer_is_guest":            "customer_is_guest",
    "customer_note_notify":         "customer_note_notify",
    "email_sent":                   "email_sent",
    "is_virtual":                   "is_virtual",
    "remote_ip":                    "remote_ip",
    "store_id":                     "store_id",
    "store_currency_code":          "store_currency_code",
    "store_name":                   "store_name",
    "shipping_description":         "shipping_description",
    "shipping_amount":              "shipping_amount",
    "shipping_tax_amount":          "shipping_tax_amount",
    "discount_amount":              "discount_amount",
    "subtotal":                     "subtotal",
    "total_paid":                   "total_paid",
    "total_due":                    "total_due",
    "grand_total":                  "grand_total",
    "total_item_count":             "total_item_count",
    "total_qty_ordered":            "total_qty_ordered",
    # Items (one row per item)
    "items.item_id":                "items_item_id",
    "items.product_id":             "items_product_id",
    "items.parent_item_id":         "items_parent_item_id",
    "items.sku":                    "items_sku",
    "items.name":                   "items_name",
    "items.free_shipping":          "items_free_shipping",
    "items.qty_ordered":            "items_qty_ordered",
    "items.qty_canceled":           "items_qty_canceled",
    "items.qty_refunded":           "items_qty_refunded",
    "items.qty_shipped":            "items_qty_shipped",
    "items.no_discount":            "items_no_discount",
    "items.discount_percent":       "items_discount_percent",
    "items.amount_refunded":        "items_amount_refunded",
    "items.discount_amount":        "items_discount_amount",
    "items.original_price":         "items_original_price",
    "items.price":                  "items_price",
    "items.price_incl_tax":         "items_price_incl_tax",
    "items.tax_amount":             "items_tax_amount",
    "items.tax_percent":            "items_tax_percent",
    "items.row_total_incl_tax":     "items_row_total_incl_tax",
    "items.row_total":              "items_row_total",
    # Billing address
    "billing_address.address_type": "billing_address_billing",
    "billing_address.entity_id":    "billing_address_entity_id",
    "billing_address.parent_id":    "billing_address_parent_id",
    "billing_address.email":        "billing_address_email",
    "billing_address.firstname":    "billing_address_firstname",
    "billing_address.lastname":     "billing_address_lastname",
    "billing_address.telephone":    "billing_address_telephone",
    "billing_address.street":       "billing_address_street",
    "billing_address.city":         "billing_address_city",
    "billing_address.postcode":     "billing_address_postcode",
    "billing_address.region_code":  "billing_address_region_code",
    "billing_address.region":       "billing_address_region",
    "billing_address.country_id":   "billing_address_country_id",
    # Payment
    "payment.parent_id":            "payment_parent_id",
    "payment.account_status":       "payment_account_status",
    "payment.method":               "payment_method",
    "payment.shipping_amount":      "payment_shipping_amount",
    "payment.shipping_captured":    "payment_shipping_captured",
    "payment.amount_authorized":    "payment_amount_authorized",
    "payment.amount_ordered":       "payment_amount_ordered",
    "payment.amount_paid":          "payment_amount_paid",
    # Extra fee
    "mp_extra_fee":                 "mp_extra_fee",
}


# ─── API 1: Authentication ────────────────────────────────────────────────────

def get_auth_access_token():
    """Get Magento bearer token (cached for 1 hour)."""
    global _cached_token, _token_expiry
    if _cached_token and _token_expiry and datetime.now() < _token_expiry:
        logging.info("Using cached auth token")
        return _cached_token
    logging.info("Fetching new auth token...")
    resp = requests.post(
        AUTH_URL,
        json={"username": USERNAME, "password": PASSWORD},
        headers={"Content-Type": "application/json"},
        timeout=30,
        verify=False,
    )
    resp.raise_for_status()
    token = resp.json()
    if not isinstance(token, str) or not token:
        raise ValueError(f"Unexpected token response: {token!r}")
    _cached_token = token
    _token_expiry = datetime.now() + timedelta(hours=1)
    logging.info("✓ Auth token obtained")
    return token


# ─── API 2: Orders ────────────────────────────────────────────────────────────

def _fetch_pages(token, date_from=None, date_to=None):
    """
    Fetch orders from Magento.
      - No dates  → single request with searchCriteria=all
      - With dates → paginated, filtered on updated_at in UTC
    """
    headers     = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    max_retries = 3

    # --ALL mode
    if not date_from and not date_to:
        logging.info("Fetching ALL orders (searchCriteria=all)...")
        for attempt in range(1, max_retries + 1):
            try:
                resp = requests.get(
                    API_URL, headers=headers,
                    params={"searchCriteria": "all"},
                    timeout=120, verify=False,
                )
                resp.raise_for_status()
                data   = resp.json()
                orders = data.get("items", [])
                logging.info(f"Fetched {len(orders)} / {data.get('total_count', len(orders))} orders")
                return orders
            except requests.exceptions.RequestException as e:
                logging.warning(f"Attempt {attempt}/{max_retries} failed: {e}")
                if attempt < max_retries:
                    time.sleep(5 * attempt)
        logging.error("Failed to fetch all orders after retries")
        return []

    # Date-filtered mode
    all_orders, page, total_count = [], 1, None
    logging.info(f"Fetching [{date_from}] → [{date_to}] (UTC, updated_at filter)...")

    while True:
        params = {
            "searchCriteria[pageSize]":    PAGE_SIZE,
            "searchCriteria[currentPage]": page,
            "searchCriteria[filter_groups][0][filters][0][field]":          "updated_at",
            "searchCriteria[filter_groups][0][filters][0][value]":          date_from,
            "searchCriteria[filter_groups][0][filters][0][condition_type]": "from",
            "searchCriteria[filter_groups][1][filters][0][field]":          "updated_at",
            "searchCriteria[filter_groups][1][filters][0][value]":          date_to,
            "searchCriteria[filter_groups][1][filters][0][condition_type]": "to",
        }
        orders, fetched = [], False
        for attempt in range(1, max_retries + 1):
            try:
                resp = requests.get(
                    API_URL, headers=headers, params=params, timeout=60, verify=False,
                )
                resp.raise_for_status()
                data        = resp.json()
                orders      = data.get("items", [])
                total_count = data.get("total_count", 0)
                all_orders.extend(orders)
                logging.info(f"Page {page}: {len(orders)} orders (running: {len(all_orders)}/{total_count})")
                fetched = True
                break
            except requests.exceptions.RequestException as e:
                logging.warning(f"Page {page} attempt {attempt}/{max_retries}: {e}")
                if attempt < max_retries:
                    time.sleep(5 * attempt)
        if not fetched:
            logging.error(f"Giving up on page {page}")
            break
        if not orders or (total_count is not None and len(all_orders) >= total_count):
            break
        page += 1
        time.sleep(0.5)

    return all_orders


# ─── Timezone helper ──────────────────────────────────────────────────────────

def vn_to_utc_str(vn_naive_str):
    """Convert "YYYY-MM-DDTHH:MM:SS" Vietnam time → "YYYY-MM-DD HH:MM:SS" UTC."""
    vn_naive = datetime.strptime(vn_naive_str.strip(), "%Y-%m-%dT%H:%M:%S")
    return VN_TZ.localize(vn_naive).astimezone(pytz.utc).strftime("%Y-%m-%d %H:%M:%S")


# ─── Data processing ──────────────────────────────────────────────────────────

def flatten_data(orders_raw):
    """Flatten orders into one row per item (billing_address, payment promoted to top level)."""
    rows = []
    for order in orders_raw:
        flat = {}
        for key, val in order.items():
            if key == "items":
                continue
            elif key == "billing_address" and isinstance(val, dict):
                for k, v in val.items():
                    flat[f"billing_address.{k}"] = (
                        " ".join(str(s) for s in v) if k == "street" and isinstance(v, list) else v
                    )
            elif key == "payment" and isinstance(val, dict):
                for k, v in val.items():
                    flat[f"payment.{k}"] = v
            elif key == "extension_attributes" and isinstance(val, dict):
                mp = val.get("mp_extra_fee")
                flat["mp_extra_fee"] = json.dumps(mp, ensure_ascii=False) if mp is not None else None
            else:
                flat[key] = val

        items = order.get("items") or []
        if items:
            for item in items:
                row = dict(flat)
                for k, v in item.items():
                    row[f"items.{k}"] = v
                rows.append(row)
        else:
            rows.append(flat)

    return pd.DataFrame(rows) if rows else pd.DataFrame()


def process_df(df):
    """Rename columns, format datetimes, clean empty lists, drop parent configurable rows."""
    # Rename & reorder
    rename_dict = {k: v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns}
    df = df.rename(columns=rename_dict)[
        [v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns]
    ]

    # created_at / updated_at → YYYYMMDDHHMMSS
    for col in ("created_at", "updated_at"):
        if col in df.columns:
            parsed  = pd.to_datetime(df[col], errors="coerce")
            df[col] = parsed.dt.strftime("%Y%m%d%H%M%S").where(parsed.notna(), df[col])

    # Replace "[]" cells with None
    for col in df.columns:
        mask = df[col].astype(str).str.strip() == "[]"
        if mask.any():
            df.loc[mask, col] = None

    # Drop parent configurable placeholder rows (items_parent_item_id is null on them)
    if "items_parent_item_id" in df.columns:
        before  = len(df)
        pid_str = df["items_parent_item_id"].astype(str).str.strip()
        df      = df[~pid_str.isin(["", "nan", "None", "NaN", "none", "null", "NULL"])]
        logging.info(f"Filtered {before - len(df)} parent rows → {len(df)} remaining")

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

# ─── BigQuery insert ──────────────────────────────────────────────────────────

def insert_to_bigquery(df):
    """Insert DataFrame into BigQuery (WRITE_APPEND). Nulls stay NULL; values cast to STRING."""
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
    
    client = (
        bigquery.Client(project=BQ_PROJECT, credentials=credentials)
        if credentials
        else bigquery.Client(project=BQ_PROJECT)
    )
    try:
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            autodetect=False,
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,
            ],
        )
        job = client.load_table_from_dataframe(
            df, client.dataset(BQ_DATASET).table(BQ_TABLE), job_config=job_config
        )
        job.result()
        logging.info(f"✓ Inserted {job.output_rows} rows → {BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}")
        return job.output_rows
    finally:
        client.close()


# ─── Core pipeline ────────────────────────────────────────────────────────────

def run_pipeline(start_vn=None, end_vn=None, fetch_all=False):
    """Authenticate → fetch → flatten → process → insert. Returns a summary dict."""
    token = get_auth_access_token()

    if fetch_all:
        raw = _fetch_pages(token)
    else:
        start_utc = vn_to_utc_str(start_vn)
        end_utc   = vn_to_utc_str(end_vn)
        logging.info(f"VN: {start_vn} → {end_vn}  |  UTC: {start_utc} → {end_utc}")

        # 30-day UTC chunks
        start_dt = datetime.strptime(start_utc, "%Y-%m-%d %H:%M:%S")
        end_dt   = datetime.strptime(end_utc,   "%Y-%m-%d %H:%M:%S")
        raw, cursor = [], start_dt
        while cursor < end_dt:
            nxt   = min(cursor + timedelta(days=30), end_dt)
            chunk = _fetch_pages(
                token,
                cursor.strftime("%Y-%m-%d %H:%M:%S"),
                nxt.strftime("%Y-%m-%d %H:%M:%S"),
            )
            raw.extend(chunk)
            cursor = nxt

    if not raw:
        return {"status": "ok", "orders_fetched": 0, "rows_inserted": 0, "message": "No data"}

    df = flatten_data(raw)
    logging.info(f"Flattened: {len(df)} rows")
    df = process_df(df)
    logging.info(f"Processed: {len(df)} rows × {len(df.columns)} columns")

    inserted = insert_to_bigquery(df)
    return {
        "status":        "ok",
        "orders_fetched": len(raw),
        "rows_inserted":  inserted,
        "date_range_vn":  f"{start_vn or 'ALL'} → {end_vn or 'ALL'}",
    }


# ─── Flask routes ─────────────────────────────────────────────────────────────

@app.route("/healthz")
def healthz():
    return jsonify({
        "status":    "ok",
        "service":   "magento-order",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    })


@app.route("/")
@app.route("/run")
def run():
    try:
        fetch_all  = request.args.get("all", "").lower() in ("1", "true", "yes")
        start_date = request.args.get("start_date")
        end_date   = request.args.get("end_date")

        if fetch_all:
            result = run_pipeline(fetch_all=True)
        elif start_date and end_date:
            result = run_pipeline(start_vn=start_date, end_vn=end_date)
        else:
            now_vn    = datetime.now(tz=VN_TZ)
            yesterday = now_vn - timedelta(days=1)
            result = run_pipeline(
                start_vn=yesterday.strftime("%Y-%m-%dT00:00:00"),
                end_vn=yesterday.strftime("%Y-%m-%dT23:59:59"),
            )

        return jsonify(result), 200

    except Exception as e:
        logging.exception("Pipeline error")
        return jsonify({"status": "error", "message": str(e)}), 500


# ─── Local entry point ────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
