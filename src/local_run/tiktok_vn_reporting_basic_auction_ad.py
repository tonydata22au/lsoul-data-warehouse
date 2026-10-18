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

load_dotenv()  # local runs read credentials from the repo-root .env; deployed services use real env vars

# Load .env that sits next to this script
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")

ACCESS_TOKEN_FROM_ENV = os.environ["TIKTOK_ACCESS_TOKEN"]
ADVERTISER_ID = "7161770060200050689"
API_URL = "https://business-api.tiktok.com/open_api/v1.3/report/integrated/get/"

# BigQuery config
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

DIMENSIONS = ["ad_id", "country_code", "stat_time_day"]

# Ordered mapping: API column name -> output column name.
# The dict order defines the fixed column order in the CSV.
COLUMN_RENAME_MAP = {
    # --- Dimensions ---
    "ad_id":                                        "ad_id",
    "country_code":                                  "country_code",
    "stat_time_day":                                 "stat_time_day",
    # --- Cost & Delivery ---
    "spend":                                         "spend",
    "cpc":                                           "cpc",
    "cpm":                                           "cpm",
    "impressions":                                   "impressions",
    "gross_impressions":                             "gross_impressions",
    "clicks":                                        "clicks",
    "ctr":                                           "ctr",
    "reach":                                         "reach",
    "frequency":                                     "frequency",

    # --- Result ---
    "result":                                        "result",
    "cost_per_result":                               "cost_per_result",
    "result_rate":                                   "result_rate",
    "real_time_result":                              "real_time_result",
    "real_time_cost_per_result":                     "real_time_cost_per_result",
    "real_time_result_rate":                         "real_time_result_rate",
    # --- Video ---
    "video_play_actions":                            "video_play_actions",
    "video_watched_2s":                              "video_watched_2s",
    "video_watched_6s":                              "video_watched_6s",
    "average_video_play":                            "average_video_play",
    "video_views_p25":                               "video_views_p25",
    "video_views_p50":                               "video_views_p50",
    "video_views_p75":                               "video_views_p75",
    "video_views_p100":                              "video_views_p100",
    "engaged_view":                                  "engaged_view",
    "engaged_view_15s":                              "engaged_view_15s",
    # --- Engagement ---
    #"clicks_on_music_disc":                          "clicks_on_music_disc",
    "follows":                                       "follows",
    "likes":                                         "likes",
    "comments":                                      "comments",
    "shares":                                        "shares",
    "profile_visits":                                "profile_visits",
    "profile_visits_rate":                           "profile_visits_rate",
    "live_product_clicks":                           "live_product_clicks",

    # --- Conversion (standard) ---
    # "conversion":                                    "conversion",
    # "cost_per_conversion":                           "cost_per_conversion",
    # "conversion_rate":                               "conversion_rate",
    # "conversion_rate_v2":                            "conversion_rate_v2",
    
    # --- Conversion (real-time) ---
    # "real_time_conversion":                          "real_time_conversion",
    # "real_time_cost_per_conversion":                 "real_time_cost_per_conversion",
    # "real_time_conversion_rate":                     "real_time_conversion_rate",
    # "real_time_conversion_rate_v2":                  "real_time_conversion_rate_v2",
    
    # --- App Install ---
    #"real_time_app_install":                         "real_time_app_install",
    #"real_time_app_install_cost":                    "real_time_app_install_cost",
    #"app_install":                                   "app_install",
    #"cost_per_app_install":                          "cost_per_app_install",
    
    # --- Registration ---
    #"registration":                                  "registration",
    #"cost_per_registration":                         "cost_per_registration",
    #"registration_rate":                             "registration_rate",
    
    # --- Purchase ---
    #"purchase":                                      "purchase",
    #"cost_per_purchase":                             "cost_per_purchase",
    #"purchase_rate":                                 "purchase_rate",
    
    # --- Complete Payment ---
    #"complete_payment":                              "complete_payment",
    #"cost_per_complete_payment":                     "cost_per_complete_payment",
    #"complete_payment_rate":                         "complete_payment_rate",
    # --- Landing Page ---
    "total_landing_page_view":                       "total_landing_page_view",
    "cost_per_landing_page_view":                    "cost_per_landing_page_view",
    "landing_page_view_rate":                        "landing_page_view_rate",
    
    # --- Page Browse ---
    #"page_browse_view":                              "page_browse_view",
    #"cost_per_page_browse_view":                     "cost_per_page_browse_view",
    #"page_browse_view_rate":                         "page_browse_view_rate",
    # --- Button Click ---
    #"button_click":                                  "button_click",
    #"cost_per_button_click":                         "cost_per_button_click",
    #"button_click_rate":                             "button_click_rate",
    
    # --- Online Consult ---
    #"online_consult":                                "online_consult",
    #"cost_per_online_consult":                       "cost_per_online_consult",
    #"online_consult_rate":                           "online_consult_rate",
    
    # --- Form ---
    #"form":                                          "form",
    #"cost_per_form":                                 "cost_per_form",
    #"form_rate":                                     "form_rate",
    
    # --- Download ---
    #"download_start":                                "download_start",
    #"cost_per_download_start":                       "cost_per_download_start",
    #"download_start_rate":                           "download_start_rate",
    
    # --- Interactive (IX) ---
    # "ix_page_duration_avg":                          "ix_page_duration_avg",
    # "ix_page_viewrate_avg":                          "ix_page_viewrate_avg",
    # "ix_video_views":                                "ix_video_views",
    # "ix_video_views_p25":                            "ix_video_views_p25",
    # "ix_video_views_p50":                            "ix_video_views_p50",
    # "ix_video_views_p75":                            "ix_video_views_p75",
    # "ix_video_views_p100":                           "ix_video_views_p100",
    # "ix_average_video_play":                         "ix_average_video_play",
   
    # --- Onsite: Add to Wishlist ---
    # "onsite_add_to_wishlist":                        "onsite_add_to_wishlist",
    # "cost_per_onsite_add_to_wishlist":               "cost_per_onsite_add_to_wishlist",
    # "onsite_add_to_wishlist_rate":                   "onsite_add_to_wishlist_rate",
    # "value_per_onsite_add_to_wishlist":              "value_per_onsite_add_to_wishlist",
    # "total_onsite_add_to_wishlist_value":            "total_onsite_add_to_wishlist_value",

    # --- IX Product Click ---
    # "ix_product_click_count":                        "ix_product_click_count",
    # "cost_per_ix_product_click_count":               "cost_per_ix_product_click_count",
    # "ix_product_click_count_rate":                   "ix_product_click_count_rate",

    # --- Onsite: Shopping ---
    # "onsite_shopping_roas":                          "onsite_shopping_roas",
    # "onsite_shopping":                               "onsite_shopping",
    # "cost_per_onsite_shopping":                      "cost_per_onsite_shopping",
    # "onsite_shopping_rate":                           "onsite_shopping_rate",
    # "value_per_onsite_shopping":                     "value_per_onsite_shopping",
    # "total_onsite_shopping_value":                   "total_onsite_shopping_value",

    # --- Onsite: Initiate Checkout ---
    # "onsite_initiate_checkout_count":                "onsite_initiate_checkout_count",
    # "cost_per_onsite_initiate_checkout_count":       "cost_per_onsite_initiate_checkout_count",
    # "onsite_initiate_checkout_count_rate":           "onsite_initiate_checkout_count_rate",
    # "value_per_onsite_initiate_checkout_count":      "value_per_onsite_initiate_checkout_count",
    # "total_onsite_initiate_checkout_count_value":    "total_onsite_initiate_checkout_count_value",
    
    # --- Onsite: Web Detail ---
    "onsite_on_web_detail":                          "onsite_on_web_detail",
    "cost_per_onsite_on_web_detail":                 "cost_per_onsite_on_web_detail",
    "onsite_on_web_detail_rate":                     "onsite_on_web_detail_rate",
    # "value_per_onsite_on_web_detail":                "value_per_onsite_on_web_detail",
    # "total_onsite_on_web_detail_value":              "total_onsite_on_web_detail_value",
    
    # --- Onsite: Web Cart ---
    # "onsite_on_web_cart":                            "onsite_on_web_cart",
    # "cost_per_onsite_on_web_cart":                   "cost_per_onsite_on_web_cart",
    # "onsite_on_web_cart_rate":                       "onsite_on_web_cart_rate",
    # "value_per_onsite_on_web_cart":                  "value_per_onsite_on_web_cart",
    # "total_onsite_on_web_cart_value":                "total_onsite_on_web_cart_value",
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
        "Access-Token": os.environ["TIKTOK_ACCESS_TOKEN"],
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
            "service_type": "AUCTION",
            "report_type": "BASIC",
            "data_level": "AUCTION_AD",
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


def insert_to_bigquery(df, project_id=None, dataset_id="raw_tiktok", table_id="raw_tiktok_reporting_basic_auction_ad"):
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
    parser = argparse.ArgumentParser(description="Export TikTok Ads reporting data to BigQuery.")
    parser.add_argument("--start-date", default=None, help="Start date YYYY-MM-DD")
    parser.add_argument("--end-date", default=None, help="End date YYYY-MM-DD")
    parser.add_argument("--list", action="store_true", help="List columns and exit")
    args = parser.parse_args()

    # --- Determine date range (default: yesterday in Vietnam time) ---
    vietnam_tz = pytz.timezone("Asia/Ho_Chi_Minh")
    now_vietnam = datetime.now(vietnam_tz)
    yesterday = now_vietnam - timedelta(days=1)

    start_date = args.start_date or yesterday.strftime("%Y-%m-%d")
    end_date = args.end_date or yesterday.strftime("%Y-%m-%d")

    # --- Fetch data (chunked into 30-day windows) ---
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