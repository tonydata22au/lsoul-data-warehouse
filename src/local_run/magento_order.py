#!/usr/bin/env python3
"""
Script to load order data from Magento API, flatten nested structures, and export to CSV.
All dates are in Vietnam time (UTC+7). The script converts them to UTC for the API.
Default: Get yesterday's orders in Vietnam time (VN T00:00:00 → T23:59:59, converted to UTC).

API flow:
  1. POST /rest/V1/integration/admin/token  → bearer token (plain string)
  2. GET  /rest/V1/orders                   → paginated order list (filters in UTC)

Usage:
    python3 local-run/magento/magento-data_export_order.py
        # Interactive prompt; defaults to yesterday (Vietnam date)
    python3 local-run/magento/magento-data_export_order.py --start_date 2025-01-01T00:00:00 --end_date 2026-07-03T23:59:59
        # Dates in Vietnam time — converted to UTC automatically
    python3 local-run/magento/magento-data_export_order.py --ALL
        # Fetch all orders with no date filter (use with caution)
"""

import sys
import json
import os
import time
import warnings
from datetime import datetime, timedelta
from pathlib import Path
import pandas as pd
import pytz
import requests
from google.cloud import bigquery
from google.oauth2 import service_account
from dotenv import load_dotenv

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)


# ─── API Configuration ────────────────────────────────────────────────────────────────
AUTH_URL  = "https://management.lsoul.com/rest/V1/integration/admin/token"
API_URL   = "https://management.lsoul.com/rest/V1/orders"
USERNAME  = os.environ["MAGENTO_USERNAME"]
PASSWORD  = os.environ["MAGENTO_PASSWORD"]
PAGE_SIZE = 1000

# User-facing timezone: all date inputs/outputs are in Vietnam time (UTC+7)
VN_TZ = pytz.timezone("Asia/Ho_Chi_Minh")

OUTPUT_DIR = Path(
    "/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/"
    "My Drive/03. CODE & DOCUMENTS/data_export_csv"
)

# BigQuery config
BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))


# ─── Token cache ────────────────────────────────────────────────────────────────
_cached_token = None
_token_expiry = None

# ─── Column mapping (API response key → CSV column name) ─────────────────────
# Keys match the flattened dict produced by flatten_data().
# billing_address.* and payment.* come from nested objects in the API response.
# mp_extra_fee is extracted from extension_attributes.mp_extra_fee (JSON string).
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
    # Extra fee (from extension_attributes.mp_extra_fee, serialised as JSON string)
    "mp_extra_fee":                 "mp_extra_fee",
}


# ─── API 1: Authentication ────────────────────────────────────────────────────
            
            #"x_forwarded_for": "x_forwarded_for",
            #"base_currency_code": "USD",
            # "base_to_global_rate": 1,
            #"base_to_order_rate": 1,
            #"base_shipping_amount": 49,
            #"base_total_paid": 512,
            #"base_discount_amount": 0,
            #"base_discount_invoiced": 0,
            #"base_grand_total": 512,
            #"base_discount_tax_compensation_amount": 0,
            #"base_discount_tax_compensation_invoiced": 0,
            #"base_shipping_discount_amount": 0,
            #"base_shipping_discount_tax_compensation_amnt": 0,
            #"base_shipping_incl_tax": 49,
            #"base_shipping_invoiced": 49,
            #"base_shipping_tax_amount": 0,
            #"base_subtotal": 455,
            #"base_subtotal_incl_tax": 455,
            #"base_subtotal_invoiced": 455,
            #"base_tax_amount": 0,
            #"base_tax_invoiced": 0,
            #"base_total_due": 0,
            #"base_total_invoiced": 512,
            #"base_total_invoiced_cost": 0,
            #"billing_address_id": 436,
            #"global_currency_code": "USD",
            # "discount_invoiced": 0,
            #"discount_tax_compensation_amount": 0,
            #"discount_tax_compensation_invoiced": 0,
            #"protect_code": "50d1ea601405cd740fc7ff640dc5b436",
            #"quote_id": 450008,
            #"shipping_discount_amount": 0,
            #"shipping_discount_tax_compensation_amount": 0,
            #"shipping_incl_tax": 49,
            #"shipping_invoiced": 49,
            #"store_to_base_rate": 0,
            #"store_to_order_rate": 0,
            #"subtotal_incl_tax": 455,
            #"subtotal_invoiced": 455,
            #"tax_amount": 0,
            #"tax_invoiced": 0,
            #"total_invoiced": 512,
            #"weight": 14,
                  
                    #"base_amount_refunded": 0,
                    #"base_discount_amount": 0,
                    #"base_discount_invoiced": 0,
                    #"base_discount_tax_compensation_amount": 0,
                    #"base_discount_tax_compensation_invoiced": 0,
                    #"base_original_price": 90,
                    #"base_price": 90,
                    #"base_price_incl_tax": 90,
                    #"base_row_invoiced": 90,
                    #"base_row_total": 90,
                    #"base_row_total_incl_tax": 90,
                    #"base_tax_amount": 0,
                    #"base_tax_invoiced": 0,
                    #"discount_invoiced": 0,
                    #"discount_tax_compensation_amount": 0,
                    #"discount_tax_compensation_invoiced": 0,
                    #"is_qty_decimal": 0,
                    #"is_virtual": 0,
                    #"product_type": "configurable",
                    #"qty_invoiced": 1,
                    #"quote_item_id": 25984,
                    #"row_invoiced": 90,
                    #"row_weight": 3,
                    #"tax_invoiced": 0,
                    #"weee_tax_applied": "[]",
                    #"weight": 3,
                    #"product_option": {
                    #"extension_attributes":
        
                #"additional_information": [
                #     "1",
                #     "",
                #     "X5VCGGEBQLP2A",
                #     "hanvo3250@gmail.com",
                #     "unverified",
                #     "Confirmed",
                #     "fd24d6000701b",
                #     "X5VCGGEBQLP2A",
                #     "EC-6UW18790T9327762H",
                #     "PayPal Express Checkout",
                #     null,
                #     "Eligible",
                #     "completed",
                #     "None"
                # ],
                # "base_amount_authorized": 512,
                # "base_amount_ordered": 512,
                # "base_amount_paid": 512,
                # "base_amount_paid_online": 512,
                # "base_shipping_amount": 49,
                # "base_shipping_captured": 49,
                # "cc_exp_year": "0",
                # "cc_last4": null,
                # "cc_ss_start_month": "0",
                # "cc_ss_start_year": "0",
                # "entity_id": 218,
                # "last_trans_id": "4AR44097FH871732N",
            # "status_histories": [
            #     {
            #         "entity_id": 163,
            #         "parent_id": 218,
            #         "created_at": "2026-06-24 14:56:16",
            #         "status": "processing"
            #         "comment": "Captured amount of $512.00 online. Transaction ID: \"<a target=\"_blank\" href=\"https://www.paypal.com/cgi-bin/webscr?cmd=_view-a-trans&id=4AR44097FH871732N\">4AR44097FH871732N</a>\"",
            #         "entity_name": "invoice",
            #         "is_customer_notified": null,
            #         "is_visible_on_front": 0,  
            #     }
            # ],
            # "extension_attributes": {
            #     "shipping_assignments": [
            #         {
            #             "shipping": {
            #                 "address": {
            #                     "address_type": "shipping",
            #                     "city": "Oviedo",
            #                     "country_id": "US",
            #                     "email": "hanvo3250@gmail.com",
            #                     "entity_id": 435,
            #                     "firstname": "Han",
            #                     "lastname": "Vo",
            #                     "parent_id": 218,
            #                     "postcode": "32766",
            #                     "region": "Florida",
            #                     "region_code": "FL",
            #                     "region_id": 18,
            #                     "street": [
            #                         "443 west county road 419",
            #                         "Suite 1021"
            #                     ],
            #                     "telephone": "4078219950"
            #                 },
            #                 "method": "mptablerate_28",
            #                 "total": {
            #                     "base_shipping_amount": 49,
            #                     "base_shipping_discount_amount": 0,
            #                     "base_shipping_discount_tax_compensation_amnt": 0,
            #                     "base_shipping_incl_tax": 49,
            #                     "base_shipping_invoiced": 49,
            #                     "base_shipping_tax_amount": 0,
            #                     "shipping_amount": 49,
            #                     "shipping_discount_amount": 0,
            #                     "shipping_discount_tax_compensation_amount": 0,
            #                     "shipping_incl_tax": 49,
            #                     "shipping_invoiced": 49,
            #                     "shipping_tax_amount": 0
            #                 }
            #             },
            #         }
            #     ],
                #"payment_additional_info":
                #"applied_taxes": [],
                #"taxes": [],
                # "mp_extra_fee": [
                #     {
                #         "code": "mp_extra_fee_rule_2_auto",
                #         "title": "Direct Signature Required",
                #         "label": "Direct Signature Required",
                #         "value": 8,
                #         "value_excl_tax": 8,
                #         "value_incl_tax": 8,
                #         "base_value": 8,
                #         "base_value_incl_tax": 8,
                #         "rf": "1",
                #         "display_area": "3",
                #         "apply_type": "1",
                #         "rule_label": "Direct Signature Required",
                #         "percent": 0
                #     }
                # ]
                #"item_applied_taxes": [],
                #"converting_from_quote": false,
                #"additional_itemized_taxes": [],


# ─── API 1: Authentication ────────────────────────────────────────────────────

def get_auth_access_token():
    """
    POST /rest/V1/integration/admin/token with username + password (JSON body).
    Magento returns the bearer token as a plain JSON string, e.g. "abc123...".
    Token is cached for 1 hour to avoid redundant requests.
    """
    global _cached_token, _token_expiry

    if _cached_token and _token_expiry and datetime.now() < _token_expiry:
        print("Using cached authentication token")
        return _cached_token

    print("Fetching new authentication token...")
    try:
        response = requests.post(
            AUTH_URL,
            json={"username": USERNAME, "password": PASSWORD},
            headers={"Content-Type": "application/json"},
            timeout=30,
            verify=False,
        )
        response.raise_for_status()
        token = response.json()

        if not isinstance(token, str) or not token:
            raise Exception(f"Unexpected token response: {token!r}")

        _cached_token = token
        _token_expiry = datetime.now() + timedelta(hours=1)
        print("✓ Authentication token obtained")
        return token

    except requests.exceptions.RequestException as e:
        raise Exception(f"Authentication request failed: {e}")

# ─── API 2: Orders (paginated) ────────────────────────────────────────────────

def _fetch_pages(token, date_from=None, date_to=None):
    """
    GET /rest/V1/orders.

    --ALL mode (no dates): sends searchCriteria=all — single request, no pagination.
    Date mode: uses searchCriteria[pageSize]/[currentPage] with date filters,
               looping until all pages are fetched.

    Args:
        token:     Magento bearer token
        date_from: "YYYY-MM-DD HH:MM:SS"  (created_at >= date_from)
        date_to:   "YYYY-MM-DD HH:MM:SS"  (created_at <= date_to)

    Returns:
        List of raw order dicts
    """
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    max_retries = 3

    # ── --ALL mode: single request with searchCriteria=all ───────────────────
    if not date_from and not date_to:
        print("  Fetching ALL orders (searchCriteria=all) ...")
        for attempt in range(1, max_retries + 1):
            try:
                print(f"  Attempt {attempt}/{max_retries}")
                resp = requests.get(
                    API_URL,
                    headers=headers,
                    params={"searchCriteria": "all"},
                    timeout=120,
                    verify=False,
                )
                resp.raise_for_status()
                data   = resp.json()
                orders = data.get("items", [])
                total  = data.get("total_count", len(orders))
                print(f"  Fetched {len(orders)} / {total} orders")
                return orders
            except requests.exceptions.RequestException as e:
                print(f"  Attempt {attempt}/{max_retries} failed: {e}")
                if attempt < max_retries:
                    time.sleep(5 * attempt)
        print("  Failed to fetch all orders.")
        return []

    # ── Date-filtered mode: paginated searchCriteria ──────────────────────────
    all_orders  = []
    page        = 1
    total_count = None

    print(f"  Fetching [{date_from}] → [{date_to}] ...")

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

        orders  = []
        fetched = False
        for attempt in range(1, max_retries + 1):
            try:
                print(f"  Page {page}, attempt {attempt}/{max_retries}")
                resp = requests.get(
                    API_URL, headers=headers, params=params, timeout=60, verify=False
                )
                resp.raise_for_status()
                data = resp.json()

                orders      = data.get("items", [])
                total_count = data.get("total_count", 0)

                all_orders.extend(orders)
                print(
                    f"  Page {page}: {len(orders)} orders "
                    f"(running total: {len(all_orders)} / {total_count})"
                )
                fetched = True
                break

            except requests.exceptions.RequestException as e:
                print(f"  Attempt {attempt}/{max_retries} failed: {e}")
                if attempt < max_retries:
                    wait = 5 * attempt
                    print(f"  Retrying in {wait}s...")
                    time.sleep(wait)

        if not fetched:
            print(f"  Giving up on page {page} after {max_retries} attempts.")
            break

        if not orders or (total_count is not None and len(all_orders) >= total_count):
            break

        page += 1
        time.sleep(0.5)

    return all_orders


# ─── Timezone helper ──────────────────────────────────────────────────────────

def vn_to_utc_str(vn_naive_str):
    """
    Convert a naive Vietnam-time string "YYYY-MM-DDTHH:MM:SS" to a UTC string
    "YYYY-MM-DD HH:MM:SS" suitable for Magento API date filters.

    Vietnam is UTC+7, so 2026-05-01T00:00:00 VN → 2026-04-30 17:00:00 UTC.
    """
    vn_naive  = datetime.strptime(vn_naive_str.strip(), "%Y-%m-%dT%H:%M:%S")
    vn_aware  = VN_TZ.localize(vn_naive)
    utc_aware = vn_aware.astimezone(pytz.utc)
    return utc_aware.strftime("%Y-%m-%d %H:%M:%S")


# ─── Orchestration ────────────────────────────────────────────────────────────

def load_data(start_date_input=None, end_date_input=None, fetch_all=False):
    """
    Obtain token → fetch pages → flatten → rename columns.
    Dates are accepted in Vietnam time (UTC+7) and converted to UTC for the API.

    Args:
        start_date_input: "YYYY-MM-DDTHH:MM:SS" in Vietnam time (UTC+7)
        end_date_input:   "YYYY-MM-DDTHH:MM:SS" in Vietnam time (UTC+7)
        fetch_all:        skip date filter when True

    Returns:
        Flat, renamed DataFrame ready for CSV export
    """
    token    = get_auth_access_token()
    all_rows = []

    if fetch_all:
        print("\n--ALL flag: fetching all orders (no date filter).")
        all_rows = _fetch_pages(token)
    else:
        try:
            # Validate format only — timezone conversion done by vn_to_utc_str
            datetime.strptime(start_date_input.strip(), "%Y-%m-%dT%H:%M:%S")
            datetime.strptime(end_date_input.strip(),   "%Y-%m-%dT%H:%M:%S")
        except ValueError:
            raise ValueError(
                "Dates must be YYYY-MM-DDTHH:MM:SS (Vietnam time) — e.g. 2026-05-07T00:00:00"
            )

        if start_date_input.strip() >= end_date_input.strip():
            raise ValueError("end_date must be later than start_date")

        # Convert Vietnam input → UTC for API
        start_utc = vn_to_utc_str(start_date_input)
        end_utc   = vn_to_utc_str(end_date_input)
        print(f"  Input  (VN time): {start_date_input.strip()} → {end_date_input.strip()}")
        print(f"  API    (UTC):     {start_utc} → {end_utc}")

        # Split into 7-day chunks (in UTC) to avoid API timeouts on large ranges
        start_utc_dt = datetime.strptime(start_utc, "%Y-%m-%d %H:%M:%S")
        end_utc_dt   = datetime.strptime(end_utc,   "%Y-%m-%d %H:%M:%S")
        chunks, cursor = [], start_utc_dt
        while cursor < end_utc_dt:
            nxt = min(cursor + timedelta(days=30), end_utc_dt)
            chunks.append((
                cursor.strftime("%Y-%m-%d %H:%M:%S"),
                nxt.strftime("%Y-%m-%d %H:%M:%S"),
            ))
            cursor = nxt

        n = len(chunks)
        print(f"  Chunks: {n}")

        for i, (cf, ct) in enumerate(chunks, 1):
            print(f"\nChunk {i}/{n}: {cf} → {ct} (UTC)")
            chunk_rows = _fetch_pages(token, cf, ct)
            all_rows.extend(chunk_rows)
            print(f"Chunk {i} done — {len(chunk_rows)} orders.")

    if not all_rows:
        print("No data fetched.")
        return pd.DataFrame()

    df = flatten_data(all_rows)
    df = rename_and_reorder_columns(df)
    df = convert_datetime_columns(df)
    df = clean_empty_lists(df)

    # Drop rows where items_parent_item_id is null/empty
    # (covers NaN, None, "nan", "None", "" after any type coercion)
    if "items_parent_item_id" in df.columns:
        before  = len(df)
        pid_str = df["items_parent_item_id"].astype(str).str.strip()
        mask    = ~pid_str.isin(["", "nan", "None", "NaN", "none", "null", "NULL"])
        df      = df[mask]
        removed = before - len(df)
        print(f"  Filtered {removed} row(s) with null items_parent_item_id → {len(df)} rows remaining")

    print(f"\nFinal dataset: {len(df)} rows × {len(df.columns)} columns")
    return df

# ─── Flatten ──────────────────────────────────────────────────────────────────

def flatten_data(orders_raw):
    """
    Convert raw Magento order dicts into a flat list of row dicts (one row per
    order item).  Nested objects are promoted to the top level with dot-prefixed
    keys so they align exactly with COLUMN_RENAME_MAP:

      billing_address  → billing_address.<field>
      payment          → payment.<field>
      extension_attributes.mp_extra_fee → mp_extra_fee  (JSON string)
      items[]          → items.<field>  (one row per item)
    """
    rows = []
    for order in orders_raw:
        flat = {}
        for key, val in order.items():
            if key == "items":
                continue  # handled per-item below
            elif key == "billing_address" and isinstance(val, dict):
                for k, v in val.items():
                    # street is a list in Magento (multi-line address)
                    if k == "street" and isinstance(v, list):
                        flat[f"billing_address.{k}"] = " ".join(str(s) for s in v)
                    else:
                        flat[f"billing_address.{k}"] = v
            elif key == "payment" and isinstance(val, dict):
                for k, v in val.items():
                    flat[f"payment.{k}"] = v
            elif key == "extension_attributes" and isinstance(val, dict):
                mp = val.get("mp_extra_fee")
                flat["mp_extra_fee"] = (
                    json.dumps(mp, ensure_ascii=False) if mp is not None else None
                )
            else:
                flat[key] = val

        items = order.get("items", [])
        if items:
            for item in items:
                row = dict(flat)
                for k, v in item.items():
                    row[f"items.{k}"] = v
                rows.append(row)
        else:
            rows.append(flat)

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    item_cols  = [c for c in df.columns if c.startswith("items.")]
    order_cols = [c for c in df.columns if not c.startswith("items.")]
    print(f"\nData structure:")
    print(f"  Raw orders  : {len(orders_raw)}")
    print(f"  Output rows : {len(df)}  (one per order item)")
    print(f"  Order-level columns : {len(order_cols)}")
    print(f"  Item-level columns  : {len(item_cols)}")
    return df


def rename_and_reorder_columns(df):
    """
    Apply COLUMN_RENAME_MAP: rename matching source columns and keep only the
    mapped columns in the order defined by the map.
    Columns absent from the API response are silently skipped with a note.
    """
    rename_dict = {k: v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns}
    df_renamed  = df.rename(columns=rename_dict)
    final_cols  = [v for k, v in COLUMN_RENAME_MAP.items() if k in df.columns]

    missing = [k for k in COLUMN_RENAME_MAP if k not in df.columns]
    if missing:
        print(f"\n  Note: {len(missing)} mapped field(s) not present in API response:")
        for m in missing:
            print(f"    • {m}")

    return df_renamed[final_cols]


def convert_datetime_columns(df):
    """
    Convert date fields created_at and updated_at from
    'YYYY-MM-DD HH:MM:SS' (or any parseable format) to 'YYYYMMDDHHMMSS'.
    Non-parseable / null values are left as-is.
    """
    for col in ("created_at", "updated_at"):
        if col in df.columns:
            df[col] = (
                pd.to_datetime(df[col], errors="coerce")
                .dt.strftime("%Y%m%d%H%M%S")
                .where(pd.to_datetime(df[col], errors="coerce").notna(), df[col])
            )
    return df


def clean_empty_lists(df):
    """
    Replace any cell whose string representation is an empty list "[]"
    with None across all columns.
    """
    for col in df.columns:
        mask = df[col].astype(str).str.strip() == "[]"
        if mask.any():
            df.loc[mask, col] = None
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

# ─── Entry point ──────────────────────────────────────────────────────────────

def insert_to_bigquery(df, project_id=None, dataset_id="magento", table_id="raw_magento_order"):
    """Insert DataFrame into BigQuery. All columns are cast to STRING, nulls preserved as NULL."""
    # Clean nulls for BigQuery
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
        print("✓ BigQuery client closed")


def main():
    """
    All dates are entered and displayed in Vietnam time (UTC+7).
    The script converts them to UTC before calling the Magento API.

    python3 magento-data_export_order.py
        # interactive prompt; defaults to yesterday (Vietnam date)
    python3 magento-data_export_order.py --ALL
        # all orders, no date filter
    python3 magento-data_export_order.py --start_date 2026-05-01T00:00:00 --end_date 2026-05-09T23:59:59
        # dates in Vietnam time — converted to UTC automatically
    """
    args = sys.argv[1:]

    if "--ALL" in args:
        print("Mode: --ALL (no date filter)")
        df    = load_data(fetch_all=True)
        label = "ALL"
    else:
        def _get_flag(flag):
            try:
                return args[args.index(flag) + 1]
            except (ValueError, IndexError):
                return None

        start_flag = _get_flag("--start_date")
        end_flag   = _get_flag("--end_date")

        if start_flag and end_flag:
            start_date_input = start_flag
            end_date_input   = end_flag
            print(f"Mode: date range (Vietnam time) {start_date_input} → {end_date_input}")
        else:
            # Compute yesterday in Vietnam timezone
            now_vn           = datetime.now(tz=VN_TZ)
            yesterday_vn     = now_vn - timedelta(days=1)
            start_date_input = yesterday_vn.strftime("%Y-%m-%dT00:00:00")
            end_date_input   = yesterday_vn.strftime("%Y-%m-%dT23:59:59")

            print("Enter the date range for orders — dates are in Vietnam time (UTC+7).")
            print("Format: YYYY-MM-DDTHH:MM:SS")
            print(f"Press Enter to use default (yesterday VN: {yesterday_vn.strftime('%Y-%m-%d')})")

            raw_start = input(f"  Start [{start_date_input}]: ").strip()
            raw_end   = input(f"  End   [{end_date_input}]: ").strip()

            start_date_input = raw_start or start_date_input
            end_date_input   = raw_end   or end_date_input

        label = (
            start_date_input[:10].replace("-", "")
            + "_"
            + end_date_input[:10].replace("-", "")
        )
        df = load_data(start_date_input, end_date_input)

    if not df.empty:
        print(f"\nInserting {len(df)} rows into BigQuery...")
        insert_to_bigquery(df)
    else:
        print("\n\u2717 No data to export.")


if __name__ == "__main__":
    main()


