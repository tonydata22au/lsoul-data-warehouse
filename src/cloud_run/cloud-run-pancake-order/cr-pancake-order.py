"""
Pancake POS orders -> BigQuery (raw_pancake.raw_order).

Fetches the orders updated in a time window from the Pancake POS API, writes one row per order item,
renames the columns (COLUMN_RENAME_MAP), casts everything to STRING and appends the rows to
raw_pancake.raw_order. Runs on Cloud Run (gunicorn app_runner:app) or as a CLI.
Default window: orders last updated yesterday, 00:00:00 to 23:59:59 Vietnam time (UTC+7).

Full setup (secret, deploy, schedule, smoke test): README.md,
"Deploy and schedule a Cloud Run service".

Deploy (from the repo root; updates the existing pancake-order service in place):
   gcloud run deploy pancake-order --source src/cloud_run/cloud-run-pancake-order \
  --project marine-cycle-484213-b4 --billing-project marine-cycle-484213-b4 --region asia-southeast1 \
  --no-allow-unauthenticated --update-secrets PANCAKE_API_KEY=pancake_pos:latest \
  --timeout 1800 --concurrency 1 --max-instances 1 --memory 1Gi
    - PANCAKE_API_KEY comes from the Secret Manager secret pancake_pos; the runtime service account
      (266174294882-compute@developer.gserviceaccount.com) has Secret Accessor on it. Without the
      variable every request fails with HTTP 500 (KeyError: 'PANCAKE_API_KEY').
    - Use the name of the existing service: a different name creates a new service.
    - --timeout covers a full run; --concurrency 1 and --max-instances 1 stop overlapping runs from
      appending the same orders twice.
    - BigQuery access uses the service identity (Application Default Credentials); the image has no
      key file. It needs BigQuery Data Editor on raw_pancake and BigQuery Job User on the project.
    - If gcloud's billing/quota_project points at another project, the source upload fails with
      "serviceusage.services.use" denied; add --billing-project marine-cycle-484213-b4.

Schedule: Cloud Scheduler job pancake-insert-raw_order (asia-southeast1) sends GET / daily at 07:20
Asia/Saigon (Vietnam time), attempt deadline 1800s, 1 retry after 600s:
    gcloud scheduler jobs update http pancake-insert-raw_order \
        --project marine-cycle-484213-b4 --location asia-southeast1 \
        --attempt-deadline 1800s --max-retry-attempts 1 --min-backoff 600s
    - Keep it after 07:00 Vietnam time. raw_order is partitioned by ingestion time in UTC, and
      stg_order and sp_core_order_insert read only the partition for today's Vietnam date, so an
      earlier load is skipped downstream.
    - The service has the invoker IAM check disabled, so the job sends no OIDC token. Don't create a
      second job for this service: each run appends its window again.

HTTP (GET or POST; every successful run appends):
    /                                                              # yesterday (default window)
    /?start_date=2026-10-01T00:00:00&end_date=2026-10-01T23:59:59  # re-run a window (Vietnam time)

CLI (from the repo root; PANCAKE_API_KEY comes from .env, BigQuery auth from
credentials/google-credentials.json when present, else Application Default Credentials):
    # Yesterday, 00:00:00 to 23:59:59 Vietnam time
    python3 src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py
    # 30 days ago 00:00:00 to yesterday 23:59:59
    python3 src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py --30days
    # Everything up to yesterday 23:59:59
    python3 src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py --All
    # An explicit window
    python3 src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py \
        --start-date 2026-10-01T00:00:00 --end-date 2026-10-01T23:59:59
    # First page only, no BigQuery load (still calls the Pancake API and logs sample rows)
    python3 src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py --max-pages 1 --dry-run
    Other flag: --project-id <id>. Without --dry-run the CLI appends, so re-running a window adds
    duplicate rows.
"""

import argparse
import json
import logging
import os
import re
import sys
import warnings
from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import pandas as pd
import requests
from dotenv import load_dotenv
from flask import Flask, request
from google.cloud import bigquery
from google.oauth2 import service_account
from pandas import json_normalize

load_dotenv()  # local runs read credentials from the repo-root .env; Cloud Run uses real env vars

# --------------------------------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------------------------------

API_URL = "https://pos.pages.fm/api/v1/shops/1942246959/orders"
PAGE_SIZE = 1000
REQUEST_TIMEOUT_SECONDS = 169

DATASET_ID = "raw_pancake"
TABLE_ID = "raw_order"

VIETNAM_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
INPUT_DATE_FORMAT = "%Y-%m-%dT%H:%M:%S"  # --start-date / ?start_date, Vietnam time
LOADED_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S"  # timestamps as loaded to BigQuery, Vietnam time

# Local runs use credentials/google-credentials.json from the repo root. The file isn't in the Cloud
# Run image (where this resolves to /credentials/...), so the service uses its own identity there.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
SERVICE_ACCOUNT_FILE = REPO_ROOT / "credentials" / "google-credentials.json"

warnings.filterwarnings("ignore", category=pd.errors.PerformanceWarning)

logger = logging.getLogger("pancake_order")

# API field (json_normalize path) -> BigQuery column, in table column order. "item_" fields come
# from each order item, the rest from the order. Commented-out fields are available but not loaded.
COLUMN_RENAME_MAP = {
    # Item info
    "item_id": "_item_id_",
    "item_product_id": "product_id",
    "item_variation_id": "variation_id",
    "item_quantity": "quantity_ordered",
    "item_return_quantity": "quantity_returned",
    "item_returning_quantity": "quantity_returning",
    "item_returned_count": "return_count",
    # "item_is_bonus_product": "is_bonus_item",
    # "item_is_composite": "is_composite_item",
    "item_is_wholesale": "is_wholesale",
    "item_is_discount_percent": "is_discount_percent",
    # "item_note": "item_notes",
    # "item_note_product": "item_product_notes",
    "item_one_time_product": "is_one_time_product",
    "item_added_to_cart_quantity": "cart_quantity",
    "item_exchange_count": "exchange_count",
    "item_discount_each_product": "unit_discount",
    "item_total_discount": "item_total_discount",
    # "item_same_price_discount": "same_price_discount",
    # "item_components": "composite_components",
    # "item_composite_item_id": "composite_parent_id",
    # "item_measure_group_id": "measure_group_id",
    #
    # Product variation info
    "item_variation_info.name": "product_name",
    "item_variation_info.exact_price": "exact_price",
    "item_variation_info.retail_price": "retail_price",
    "item_variation_info.retail_price_original": "original_retail_price",
    "item_variation_info.avg_price": "average_price",
    "item_variation_info.last_imported_price": "last_import_price",
    # "item_variation_info.barcode": "product_barcode",
    # "item_variation_info.brand_id": "brand_id",
    # "item_variation_info.tax_rate": "tax_rate_percent",
    # "item_variation_info.weight": "product_weight",
    # "item_variation_info.display_id": "product_display_id",
    # "item_variation_info.product_display_id": "product_display_id",
    # "item_variation_info.category_ids": "product_category_ids",
    "item_variation_info.detail": "product_detail",
    "item_variation_info.fields": "product_fields",
    # "item_variation_info.images": "product_images",
    # "item_variation_info.is_upsale_product": "is_upsale",
    # "item_variation_info.measure_info": "measure_info",
    #
    # Order IDs and Status
    "id": "order_id",
    "system_id": "system_id",
    "status": "status",
    "status_name": "status_name",
    # "sub_status": "sub_status",
    "inserted_at": "inserted_at",
    "updated_at": "updated_at",
    "received_at_shop": "is_received_at_shop",
    #
    # Financial
    "order_currency": "order_currency",
    "total_price": "total_price",
    "total_price_after_sub_discount": "total_price_after_sub_discount",
    "total_discount": "total_discount",
    "total_quantity": "total_quantity",
    "shipping_fee": "shipping_fee",
    "fee_marketplace": "marketplace_fee",
    "partner_fee": "partner_fee",
    "surcharge": "surcharge_amount",
    "buyer_total_amount": "buyer_total_amount",
    "money_to_collect": "cod_money_to_collect",
    "cod": "cod",
    "tax": "tax_amount",
    #
    # Payments
    "cash": "paid_cash",
    "prepaid": "prepaid_amount",
    # "prepaid_by_point.money": "prepaid_by_points",
    "transfer_money": "transfer_amount",
    "charged_by_card": "charged_by_card",
    "charged_by_momo": "charged_by_momo",
    "charged_by_qrpay": "charged_by_qrpay",
    "bank_payments": "bank_payments",
    "exchange_payment": "exchange_payment_info",
    "customer_pay_fee": "is_customer_paid_fee",
    #
    # Shipping & Address
    "shipping_address.commune_name": "shipping_address_commune_name",
    "shipping_address.province_name": "shipping_address_province_name",
    # "bill_full_name": "billing_name",
    # "bill_phone_number": "billing_phone",
    # "bill_email": "billing_email",
    #
    # Warehouse & Shop
    "warehouse_id": "warehouse_id",
    "warehouse_info.name": "warehouse_info_name",
    # "shop_id": "shop_id",
    "marketplace_id": "marketplace_id",
    #
    # Links & Tracking
    # "link": "link",
    # "tracking_link": "tracking_link",
    "order_sources": "order_sources",
    "order_sources_name": "order_sources_name",
    # "ad_id": "ad_id",
    # "page_id": "page_id",
    # "page": "page_info",
    #
    # Notes & Tags
    "note": "notes",
    "note_print": "print_notes",
    # "note_image": "image_notes",
    "tags": "tags",
    #
    # Customer Info
    "customer.currency": "customer_currency",
    "customer.customer_id": "customer_customer_id",
    "customer.succeed_order_count": "customer_succeed_order_count",
    "customer.inserted_at": "customer_inserted_at",
    "customer.is_block": "customer_is_block",
    "customer.updated_at": "customer_updated_at",
    "customer.order_count": "customer_order_count",
    "customer.returned_order_count": "customer_returned_order_count",
    "customer.purchased_amount": "customer_purchased_amount",
    "customer.last_order_at": "customer_last_order_at",
    "customer.gender": "customer_gender",
    #
    # Assignment & Care (JSON Normalized)
    "assigning_seller.name": "assigning_seller_name",
    "assigning_seller.email": "assigning_seller_email",
    # "assigning_seller.id": "assigned_seller_id",
    "assigning_care.name": "assigning_care_name",
    "assigning_care.email": "assigning_care_email",
    # "assigning_care.id": "assigning_care_id",
    #
    # Time tracking
    "time_assign_seller": "time_assigned_seller",
    "time_assign_care": "time_assigned_care",
    "time_send_partner": "time_sent_partner",
    #
    # Returns & Exchange
    "is_exchange_order": "is_exchange_order",
    "exchange_value": "exchange_value",
    "returned_reason": "return_reason_code",
    "returned_reason_name": "return_reason",
    # "return_fee": "return_fee",
    #
    # Marketing & UTM
    # "p_utm_source": "utm_source",
    # "p_utm_medium": "utm_medium",
    # "p_utm_campaign": "utm_campaign",
    # "p_utm_content": "utm_content",
    # "p_utm_term": "utm_term",
    # "p_utm_id": "utm_id",
    #
    # Promotions & Features
    # "activated_promotion_advances": "activated_promotions",
    # "activated_combo_products": "activated_combos",
    # "levera_point": "levera_points",
    #
    # Status Tracking
    # "status_history": "status_history",
    # "histories": "full_history",
    #
    # last_editor (JSON Normalized)
    "last_editor.name": "last_editor_name",
    "last_editor.email": "last_editor_email",
    #
    # Flags
    # "is_free_shipping": "is_free_shipping",
    # "is_livestream": "is_livestream_order",
    # "is_live_shopping": "is_live_shopping",
    # "is_smc": "is_smc",
    #
    # Other
    # "conversation_id": "conversation_id",
    # "estimate_delivery_date": "estimated_delivery_date",
    # "currency": "currency",
    # "customer_needs": "customer_special_needs",
    # "botcake_info": "botcake_info",
    # "ads_source": "ads_source",
    # "marketer": "marketer_name",
    # "pke_mkter": "pke_marketer",
    #
    # creator (JSON Normalized)
    "creator.name": "creator_name",
    "creator.email": "creator_email",
    #
    # "account": "account_info",
    # "account_name": "account_name",
    "partner": "partner",
    "items_length": "items_count",
    # "post_id": "post_id",
    #
    # advanced_platform_fee (JSON Normalized)
    "advanced_platform_fee.affiliate_commission": "advanced_platform_fee_affiliate_commission",
    "advanced_platform_fee.diff_shipping_fee": "advanced_platform_fee_diff_shipping_fee",
    "advanced_platform_fee.marketplace_voucher": "advanced_platform_fee_marketplace_voucher",
    "advanced_platform_fee.payment_fee": "advanced_platform_fee_payment_fee",
    "advanced_platform_fee.seller_transaction_fee": "advanced_platform_fee_seller_transaction_fee",
    "advanced_platform_fee.service_fee": "advanced_platform_fee_service_fee",
    # "advanced_platform_fee.sfp_service_fee": "advanced_platform_fee_sfp_service_fee",
    #
    # "additional_info": "additional_info",
    # "tax": "tax_amount",
}

# Order-level fields repeated on every item row (json_normalize meta), derived from the map above
# so a new order-level column only needs adding there. Nested fields become paths, e.g.
# ["customer", "gender"].
ORDER_META_FIELDS = [
    key.split(".") if "." in key else key
    for key in COLUMN_RENAME_MAP
    if not key.startswith("item_")
]

# Loaded columns holding API timestamps (UTC), converted to Vietnam time in LOADED_TIMESTAMP_FORMAT
TIMESTAMP_COLUMNS = [
    "inserted_at",
    "updated_at",
    "time_assigned_seller",
    "time_assigned_care",
    "time_sent_partner",
    "customer_inserted_at",
    "customer_updated_at",
    "customer_last_order_at",
]

BOOLEAN_TO_BINARY = {True: 1, "True": 1, False: 0, "False": 0}


# --------------------------------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------------------------------


class CloudLoggingFormatter(logging.Formatter):
    """One JSON object per line, so Cloud Logging records each line's severity (text gets none)."""

    def format(self, record: logging.LogRecord) -> str:
        message = record.getMessage()
        if record.exc_info:
            message = f"{message}\n{self.formatException(record.exc_info)}"
        entry = {"severity": record.levelname, "message": message, "logger": record.name}
        return json.dumps(entry, ensure_ascii=False)


def configure_logging() -> None:
    """Log JSON on Cloud Run (K_SERVICE is set there) and plain messages elsewhere, to stdout."""
    handler = logging.StreamHandler(sys.stdout)
    if os.environ.get("K_SERVICE"):
        handler.setFormatter(CloudLoggingFormatter())
    else:
        handler.setFormatter(logging.Formatter("%(message)s"))
    logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)


configure_logging()


# --------------------------------------------------------------------------------------------------
# Date window
# --------------------------------------------------------------------------------------------------


def parse_date_to_unix(date_string: str | None) -> int | None:
    """Convert 'YYYY-MM-DDTHH:MM:SS' in Vietnam time to a Unix timestamp; None or blank -> None."""
    if not date_string or not date_string.strip():
        return None
    try:
        local_time = datetime.strptime(date_string, INPUT_DATE_FORMAT).replace(tzinfo=VIETNAM_TZ)
    except ValueError:
        raise ValueError(
            f"Invalid date format: {date_string}. Expected format: YYYY-MM-DDTHH:MM:SS"
        ) from None
    return int(local_time.timestamp())


def resolve_window(
    *,
    all_flag: bool = False,
    start_date: str | None = None,
    end_date: str | None = None,
    last_30_days: bool = False,
    now: datetime | None = None,
) -> tuple[str | None, str | None]:
    """
    Return the (start, end) window in Vietnam time. The first option that applies wins:
    all_flag (everything up to yesterday), explicit dates, last_30_days, then yesterday.
    """
    now = now or datetime.now(VIETNAM_TZ)
    yesterday = now - timedelta(days=1)
    end_of_yesterday = yesterday.strftime("%Y-%m-%dT23:59:59")
    if all_flag:
        # Capped at yesterday so a partial current day is never loaded
        return None, end_of_yesterday
    if start_date or end_date:
        return start_date, end_date
    if last_30_days:
        return (now - timedelta(days=30)).strftime("%Y-%m-%dT00:00:00"), end_of_yesterday
    return yesterday.strftime("%Y-%m-%dT00:00:00"), end_of_yesterday


# --------------------------------------------------------------------------------------------------
# Extract
# --------------------------------------------------------------------------------------------------


def redact_api_key(text: object) -> str:
    """Mask the api_key query parameter; requests puts the full URL in its error messages."""
    return re.sub(r"api_key=[^&\s'\"]+", "api_key=***", str(text))


def _log_window(label: str, date_string: str | None, timestamp: int | None) -> None:
    if timestamp:
        utc_time = datetime.fromtimestamp(timestamp, tz=UTC).strftime("%Y-%m-%d %H:%M:%S")
        logger.info(
            "  %s date (Vietnam/Input): %s → UTC: %s (Unix: %s)",
            label,
            date_string,
            utc_time,
            timestamp,
        )


def load_data(
    start_date: str | None = None, end_date: str | None = None, max_pages: int | None = None
) -> list[dict[str, Any]]:
    """
    Fetch orders updated between start_date and end_date ('YYYY-MM-DDTHH:MM:SS', Vietnam time; None
    means no bound), following pagination. max_pages limits the pages fetched (for testing).
    """
    api_key = os.environ["PANCAKE_API_KEY"]
    start_timestamp = parse_date_to_unix(start_date)
    end_timestamp = parse_date_to_unix(end_date)

    logger.info("Fetching data from API...")
    if start_timestamp or end_timestamp:
        _log_window("Start", start_date, start_timestamp)
        _log_window("End", end_date, end_timestamp)
    else:
        logger.info("  No date filters applied - fetching all data")

    all_orders: list[dict[str, Any]] = []
    page = 1
    with requests.Session() as session:
        while True:
            if max_pages and page > max_pages:
                logger.info("  Reached max_pages=%s, stopping fetch", max_pages)
                break
            params: dict[str, Any] = {
                "api_key": api_key,
                "page": page,
                "page_size": PAGE_SIZE,
                "updateStatus": "updated_at",  # filter on the order's last update time
            }
            if start_timestamp:
                params["startDateTime"] = start_timestamp
            if end_timestamp:
                params["endDateTime"] = end_timestamp

            # "from None" drops the original exception: its message and traceback contain the
            # request URL with the API key, which must not reach Cloud Logging or the HTTP response.
            try:
                response = session.get(API_URL, params=params, timeout=REQUEST_TIMEOUT_SECONDS)
                response.raise_for_status()
                payload = response.json()

                orders = payload.get("data", [])
                if not orders:
                    break

                all_orders.extend(orders)
                total_pages = payload.get("total_pages", 1)
                logger.info(
                    "  Fetched page %s/%s: %s orders (total: %s)",
                    page,
                    total_pages,
                    len(orders),
                    len(all_orders),
                )

                # A short page at or past the reported last page is the end
                if len(orders) < PAGE_SIZE and page >= total_pages:
                    break
                page += 1
            except requests.exceptions.RequestException as exc:
                raise ValueError(f"API request failed: {redact_api_key(exc)}") from None
            except Exception as exc:
                raise ValueError(f"Failed to parse API response: {redact_api_key(exc)}") from None

    logger.info("✓ Successfully fetched %s orders from API", len(all_orders))
    return all_orders


# --------------------------------------------------------------------------------------------------
# Transform
# --------------------------------------------------------------------------------------------------


def flatten_data(orders_raw: list[dict[str, Any]]) -> pd.DataFrame:
    """One row per order item (order fields repeated on each); orders without items stay one row."""
    has_items = any(
        isinstance(order.get("items"), list) and order.get("items") for order in orders_raw
    )

    if has_items:
        df = json_normalize(
            orders_raw,
            record_path="items",
            meta=ORDER_META_FIELDS,
            record_prefix="item_",
            meta_prefix="",
            sep=".",
            errors="ignore",
        )
        item_columns = sum(1 for column in df.columns if column.startswith("item_"))
        logger.info("Data Structure:")
        logger.info("  Orders from API: %s", len(orders_raw))
        logger.info("  Order items (rows): %s", len(df))
        logger.info("  Note: Each order item creates a separate row in the table")
        logger.info("  Item-level columns: %s", item_columns)
        logger.info("  Order-level columns: %s", len(df.columns) - item_columns)
    else:
        df = json_normalize(orders_raw, sep=".", errors="ignore")
        logger.info("Data Structure:")
        logger.info("  Orders from API: %s", len(orders_raw))
        logger.info("  Rows to insert: %s", len(df))

    return df.copy()


def rename_and_reorder_columns(df: pd.DataFrame) -> pd.DataFrame:
    """
    Keep only the columns in COLUMN_RENAME_MAP, renamed and in map order. Columns the API didn't
    return are left out; the load adds new table columns when the API starts sending them.
    """
    return pd.DataFrame(
        {new: df[original] for original, new in COLUMN_RENAME_MAP.items() if original in df.columns}
    )


def convert_booleans_to_binary(df: pd.DataFrame) -> pd.DataFrame:
    """Map True/False (bool or string) to 1/0 in every column that contains them."""
    for column in df.columns:
        if df[column].astype(str).isin(["True", "False"]).any():
            df[column] = df[column].map(lambda value: BOOLEAN_TO_BINARY.get(value, value))
    return df


def convert_dates_to_timestamp(df: pd.DataFrame) -> pd.DataFrame:
    """Convert API timestamps (UTC) to Vietnam time as YYYYMMDDHHMMSS strings."""
    for column in TIMESTAMP_COLUMNS:
        if column in df.columns:
            try:
                df[column] = (
                    pd.to_datetime(df[column], utc=True)
                    .dt.tz_convert(VIETNAM_TZ)
                    .dt.strftime(LOADED_TIMESTAMP_FORMAT)
                )
            except Exception:
                # A column that doesn't parse is loaded as the API sent it
                pass
    return df


def clean_empty_json(df: pd.DataFrame) -> pd.DataFrame:
    """In object columns, turn NaN/None and empty JSON ({} and []) into empty strings."""
    for column in df.columns:
        if df[column].dtype == "object":
            df[column] = df[column].astype(str).replace(["nan", "{}", "[]", "None"], "")
    return df


def cast_to_strings(df: pd.DataFrame) -> pd.DataFrame:
    """Cast every column to string for the all-STRING raw table."""
    for column in df.columns:
        df[column] = df[column].astype(str).replace("nan", "").replace("None", "")
    return df


# --------------------------------------------------------------------------------------------------
# Load
# --------------------------------------------------------------------------------------------------


def insert_to_bigquery(
    df: pd.DataFrame,
    project_id: str | None = None,
    dataset_id: str = DATASET_ID,
    table_id: str = TABLE_ID,
) -> str:
    """Append df to dataset_id.table_id (project_id defaults to the client's project)."""
    unique_orders = df["order_id"].nunique() if "order_id" in df.columns else len(df)
    total_rows = len(df)

    # The local service-account key when it exists; otherwise Application Default Credentials
    credentials = (
        service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))
        if SERVICE_ACCOUNT_FILE.exists()
        else None
    )
    client = bigquery.Client(project=project_id, credentials=credentials)
    try:
        table_ref = bigquery.DatasetReference(client.project, dataset_id).table(table_id)
        # No explicit schema: the load matches columns to the existing table's schema
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            autodetect=False,
            schema_update_options=[
                bigquery.SchemaUpdateOption.ALLOW_FIELD_RELAXATION,  # required -> nullable
                bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,  # new columns from the API
            ],
        )
        load_job = client.load_table_from_dataframe(
            cast_to_strings(df), table_ref, job_config=job_config
        )
        load_job.result()  # wait for completion; raises if the load failed

        message = (
            f"✓ Successfully loaded {load_job.output_rows} rows to {dataset_id}.{table_id}"
            f" [{load_job.job_id}]\n"
            f"Unique entries: {unique_orders}\n"
            f"Total rows (total entries): {total_rows}"
        )
        logger.info(message)
        return message
    finally:
        client.close()
        logger.info("✓ BigQuery client closed")


# --------------------------------------------------------------------------------------------------
# Run (shared by the CLI and the HTTP route)
# --------------------------------------------------------------------------------------------------


def run_export(
    *,
    project_id: str | None = None,
    all_flag: bool = False,
    start_date: str | None = None,
    end_date: str | None = None,
    max_pages: int | None = None,
    dry_run: bool = False,
    last_30_days: bool = False,
) -> tuple[str, int]:
    """Fetch, transform and load one window; return (message, HTTP status)."""
    window_start, window_end = resolve_window(
        all_flag=all_flag, start_date=start_date, end_date=end_date, last_30_days=last_30_days
    )
    orders_raw = load_data(start_date=window_start, end_date=window_end, max_pages=max_pages)
    if not orders_raw:
        message = "0 entry found. No data to export."
        logger.info(message)
        return message, 200

    df = flatten_data(orders_raw)
    df = rename_and_reorder_columns(df)
    df = convert_booleans_to_binary(df)
    df = convert_dates_to_timestamp(df)
    df = clean_empty_json(df)

    if dry_run:
        unique_orders = df["order_id"].nunique() if "order_id" in df.columns else len(df)
        logger.info("DRY RUN: %s rows ready for load (unique orders: %s)", len(df), unique_orders)
        logger.info("%s", df.head())
        return "Dry run complete", 200

    return insert_to_bigquery(df, project_id=project_id), 200


# --------------------------------------------------------------------------------------------------
# Entry points
# --------------------------------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Export Pancake POS order data to BigQuery")
    parser.add_argument(
        "--project-id", default=None, help="Google Cloud project ID (default: the client's project)"
    )
    parser.add_argument("--All", action="store_true", help="Fetch everything up to yesterday")
    parser.add_argument(
        "--30days",
        dest="last_30_days",
        action="store_true",
        help="Fetch from 30 days ago 00:00:00 to yesterday 23:59:59 (Vietnam time)",
    )
    parser.add_argument(
        "--start-date", default=None, help="Start, YYYY-MM-DDTHH:MM:SS in Vietnam time"
    )
    parser.add_argument("--end-date", default=None, help="End, YYYY-MM-DDTHH:MM:SS in Vietnam time")
    parser.add_argument(
        "--max-pages",
        type=int,
        default=None,
        help="Limit the number of pages fetched (for testing)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Fetch and transform only; skip the BigQuery load"
    )
    args = parser.parse_args(argv)

    if args.last_30_days and (args.All or args.start_date or args.end_date):
        parser.error("--30days cannot be combined with --All, --start-date or --end-date")

    run_export(
        project_id=args.project_id,
        all_flag=args.All,
        start_date=args.start_date,
        end_date=args.end_date,
        max_pages=args.max_pages,
        dry_run=args.dry_run,
        last_30_days=args.last_30_days,
    )


app = Flask(__name__)


# Cloud Scheduler HTTP jobs send POST unless configured otherwise; GET serves manual runs and the
# existing pancake-insert-raw_order job.
@app.route("/", methods=["GET", "POST"])
def run() -> tuple[str, int]:
    start_date = request.args.get("start_date")
    end_date = request.args.get("end_date")
    logger.info("Triggering Pancake order data export (HTTP)...")
    try:
        parse_date_to_unix(start_date)
        parse_date_to_unix(end_date)
    except ValueError as exc:
        return f"Error: {exc}", 400
    try:
        return run_export(start_date=start_date, end_date=end_date)
    except Exception as exc:
        logger.exception("Export failed")
        return f"Error: {exc}", 500


if __name__ == "__main__":
    main()
