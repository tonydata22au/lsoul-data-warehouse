# Pipeline inventory

Verified by reading the code on 2026-10-18 (nothing was executed against APIs or BigQuery).
`scripts/validate_repo.py` fails if a pipeline file is missing from this page.

**Legend**
- **Project:** the client's default project unless noted. The warehouse SQL uses `marine-cycle-484213-b4`.
- **WA:** `load_table_from_dataframe` with `WRITE_APPEND`, `ALLOW_FIELD_ADDITION`/`RELAXATION`, every column cast to STRING. Raw tables are ingestion-time partitioned.
- **VN yesterday:** 00:00:00–23:59:59 yesterday in `Asia/Ho_Chi_Minh`.
- **Schedule:** **unknown for every pipeline.** No Cloud Scheduler, cron, CI or service URLs are in the repo. The SQL implies a daily run (see [architecture.md](architecture.md#runtime-and-deployment)).
- **Dry run** (where it exists) **still calls the source API**; it only skips the BigQuery load.

## Cloud Run services: `src/cloud_run/<service>/`

Entry point for every service: `gunicorn app_runner:app` (Dockerfile). A request to `/` runs the export
with the default window below. The CLI is `python cr-<name>.py [flags]` in the same folder.

| Service folder | Source endpoint | Default window (HTTP `/`) | CLI flags | Destination | Load |
|---|---|---|---|---|---|
| cloud-run-dianplus-inventory | Dianplus `inventory/getInvs` | VN yesterday (sent as Shanghai time); HTTP also takes `?start_date`, `?end_date`, `?all=true` | `--project-id --start_date --end_date --ALL --dry-run` | `dianplus.raw_dianplus_inventory` | WA |
| cloud-run-dianplus-order | Dianplus `order/getOrder` | VN yesterday; ranges > 15 days chunked | `--start-date --end-date --project-id --dry-run` | `dianplus.raw_dianplus_order` | WA |
| cloud-run-dianplus-order-refund | Dianplus `order/getRefundOrder` | VN yesterday | `--start-date --end-date --project-id --dry-run` | `dianplus.raw_dianplus_order_refund` | WA |
| cloud-run-dianplus-product | Dianplus `sku/getSku` | Full snapshot | `--project-id --dry-run` | `dianplus.raw_dianplus_product` | WA (full catalogue appended each run) |
| cloud-run-jushuitan-order | Jushuitan `/open/orders/single/query` | Yesterday by container clock (UTC on Cloud Run); 7-day chunks | `--start-date --end-date --project-id --all --dry-run` | `jushuitan.raw_jushuitan_order` | WA |
| cloud-run-magento-order | Magento `/rest/V1/orders` | VN yesterday (sent as UTC), 30-day chunks; routes `/`, `/run`, `/healthz`; `?all=1` or `?start_date&end_date` | none: running the file starts Flask on `$PORT`; no dry run | `${BQ_PROJECT:-marine-cycle-484213-b4}.${BQ_DATASET:-magento}.${BQ_TABLE:-raw_magento_order}` | WA |
| cloud-run-meta-ads-reporting-a | Meta Graph v24.0 `/{account}/insights` (ad level, daily) | `date_preset=yesterday` | `--project-id --dataset-id --table-id --date-preset --all`; no dry run | `raw_meta.raw_ads_reporting_a` (creates dataset if missing) | WA |
| cloud-run-meta-ads-reporting-ecom | Same, plus impressions/frequency | `date_preset=yesterday` | same as above | `raw_meta.raw_ads_reporting_ecom` | WA |
| cloud-run-pancake-customer | Pancake `/customers` | VN yesterday | `--project-id --All --start-date --end-date --max-pages --dry-run` | `raw_pancake.raw_customer` | WA |
| cloud-run-pancake-ecom-product | Pancake `/marketplace/products` | VN yesterday | same Pancake flags | `raw_pancake.raw_ecom_product` | WA |
| cloud-run-pancake-inventory_histories | Pancake `/inventory_histories` | VN yesterday | Pancake flags + `--yesterday` (no effect) | `raw_pancake.raw_inventory_histories` | WA |
| cloud-run-pancake-order | Pancake `/orders` | **Last 30 days** to VN yesterday | Pancake flags | `raw_pancake.raw_order` | WA |
| cloud-run-pancake-order_returned | **Same code as pancake-order** (`/orders`) ⚠ | Last 30 days | Pancake flags | **`raw_pancake.raw_order`** ⚠ (see [known issues](troubleshooting.md#known-issues)) | WA |
| cloud-run-pancake-product | Pancake `/products` | VN yesterday | Pancake flags | `raw_pancake.raw_product` | WA |
| cloud-run-pancake-product_variations | Pancake `/products/variations` | VN yesterday | Pancake flags + `--yesterday` (ignored) | `raw_pancake.raw_product_variations` | WA |
| cloud-run-pancake-stats_inventory_product | Pancake `/inventory_analytics/inventory_by_product` | VN yesterday | Pancake flags | `raw_pancake.raw_stats_inventory_product` | WA |
| cloud-run-pancake-stats_inventory_variations | Pancake `/inventory_analytics/inventory` | VN yesterday | Pancake flags | `raw_pancake.raw_stats_inventory_variations` | WA |
| cloud-run-pancake-stats_order | Pancake `/analytics/sale` | VN yesterday | Pancake flags | `raw_pancake.raw_stats_order` | WA |
| cloud-run-pancake-stats_product | Same endpoint/params as stats_inventory_product | VN yesterday | Pancake flags | `raw_pancake.raw_stats_product` | WA |
| cloud-run-pancake-variations | Pancake `/variations` | **Full snapshot** over HTTP (CLI default filters to yesterday client-side) | Pancake flags | `raw_pancake.raw_variations` | WA |
| cloud-run-pancake-warehouse_transfer | Pancake `/transfers` | VN yesterday | Pancake flags | `raw_pancake.raw_warehouse_transfers_completed` | WA |
| cloud-run-surfosm-inventory | Surfosm `/openapi/inventory` | Yesterday by container clock; routes `/`, `/run`, `/healthz`; `?date`, `?start_date&end_date`, `?dry_run=1`. `main.py` is a Cloud Functions entry point (`export_inventory`) | `--date --start_date --end_date --dry_run --project_id` | `${BQ_DATASET:-surfosm}.${BQ_TABLE:-raw_surfosm_inventory}`; project from `GCP_PROJECT` / `GOOGLE_CLOUD_PROJECT` | WA |
| cloud-run-surfosm-order | Surfosm `/orders/list` + `/order/{n}/price-details` | **31 days** to yesterday (container clock) | `--project_id --yesterday --date --start_date --end_date --dry_run --http` | `surfosm.raw_surfosm_order` | WA |
| cloud-run-surfosm-order_return | Surfosm `/return-documents/list` + return details | 31 days to yesterday | same as surfosm-order | `surfosm.raw_surfosm_order_return` | WA |
| cloud-run-tiktok-ads | TikTok `/ad/get/` (VN account) | **Full snapshot** of all ads | `--start-date --end-date --dry-run` | `raw_tiktok.raw_tiktok_ads` | WA |
| cloud-run-tiktok-gmv-max-report | TikTok `/gmv_max/report/get/` | VN yesterday, 30-day chunks | same as tiktok-ads | `raw_tiktok.raw_tiktok_gmv_max_report` | WA |
| cloud-run-tiktok-reporting-basic-autction-ad | TikTok `/report/integrated/get/` | VN yesterday | same | `raw_tiktok.raw_tiktok_reporting_basic_auction_ad` | WA |
| cloud-run-tiktok-thai-ads | TikTok `/ad/get/` (Thai account) | Full snapshot | same | `raw_tiktok.raw_tiktok_thai_ads` | WA. ⚠ **Can't start** (see known issues) |
| cloud-run-tiktok-thai-gmv-max-report | TikTok `/gmv_max/report/get/` | VN yesterday | same | `raw_tiktok.raw_tiktok_thai_gmv_max_report` | WA |
| cloud-run-tiktok-thai-reporting-basic-autction-ad | TikTok `/report/integrated/get/` | VN yesterday | same | `raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad` | WA |

Credentials (env vars): Pancake `PANCAKE_API_KEY`; Dianplus `DIANPLUS_APP_KEY`, `DIANPLUS_APP_SECRET`;
Jushuitan `JUSHUITAN_APP_KEY`, `JUSHUITAN_APP_SECRET`; Magento `MAGENTO_USERNAME`, `MAGENTO_PASSWORD`;
Surfosm `SURFOSM_API_KEY`; Meta `META_ACCESS_TOKEN`; TikTok VN `TIKTOK_VN_ACCESS_TOKEN`, Thai `TIKTOK_TH_ACCESS_TOKEN`.
BigQuery auth: Application Default Credentials (the Cloud Run service identity).

## Local runners: `src/local_run/`

Run as `python src/local_run/<file> [flags]`. All load with **WA** to the same tables as their Cloud
Run counterparts unless noted. There's **no dry-run flag**; `--list` (TikTok scripts and
`pancake_orders_returned.py`) fetches, prints columns and exits before loading. Every script reads the
service-account key at import (`GOOGLE_APPLICATION_CREDENTIALS`, default `src/credentials/google-credentials.json`).

| File | Source | Default window | Flags | Destination |
|---|---|---|---|---|
| dianplus_inventory.py | Dianplus inventory | VN yesterday | `--start_date --end_date --ALL` | `dianplus.raw_dianplus_inventory` |
| dianplus_order.py | Dianplus orders | VN yesterday | `--start_date --end_date` | `dianplus.raw_dianplus_order` |
| dianplus_order_refund.py | Dianplus refunds | VN yesterday | `--start_date --end_date` | `dianplus.raw_dianplus_order_refund` |
| dianplus_product.py | Dianplus SKUs | Full snapshot | none | `dianplus.raw_dianplus_product` |
| jushuitan_inventory.py | Jushuitan `/open/inventory/query` | Prompts with `input()`; default yesterday | `--ALL --start_date --end_date --debug` | `jushuitan.raw_jushuitan_inventory` (local only) |
| jushuitan_order.py | Jushuitan orders | Prompts with `input()`; default yesterday | `--ALL` | `jushuitan.raw_jushuitan_order` |
| jushuitan_order_taobao_tmal_manual_import.py | Newest Excel file in `seeds/jushuitan_taobao_tmall_raw_data/` (no API) | n/a | none | `jushuitan.raw_jushuitan_taobao_tmall_order_manual` |
| magento_order.py | Magento orders | Prompts; default VN yesterday | `--ALL --start_date --end_date` | `magento.raw_magento_order` |
| meta_ads_a.py | Meta insights | `date_preset=yesterday` | `--project-id --dataset-id --table-id --date-preset --all` | `raw_meta.raw_ads_reporting_a` |
| meta_ads_ecom.py | Meta insights | same | same | `raw_meta.raw_ads_reporting_ecom` |
| meta_ads_my.py | Meta insights | same | same | `raw_meta.raw_ads_reporting_my` (local only) |
| pancake_customer.py | Pancake customers | VN yesterday | `--project-id --All --start-date --end-date` | `raw_pancake.raw_customer` |
| pancake_inventory_histories.py | Pancake inventory histories | VN yesterday | `--project-id --All --start-date --end-date --yesterday` | `raw_pancake.raw_inventory_histories` |
| pancake_order.py | Pancake orders | Last 30 days | `--project-id --All --start-date --end-date` | `raw_pancake.raw_order` |
| pancake_orders_returned.py | Pancake `/orders_returned` | Last 30 days | `--list --project-id --All --start-date --end-date` | `raw_pancake.raw_orders_returned` |
| pancake_product_variations.py | Pancake product variations | VN yesterday | `--project-id --All --start-date --end-date --yesterday` | `raw_pancake.raw_product_variations` |
| pancake_stats_inventory_variations.py | Pancake inventory analytics | VN yesterday | `--project-id --All --start-date --end-date` | `raw_pancake.raw_stats_inventory_variations` |
| pancake_stats_product.py | Pancake inventory by product | VN yesterday | `--project-id --All --start-date --end-date` | `raw_pancake.raw_stats_product` |
| surfosm_inventory.py | Surfosm inventory | Yesterday (local clock) | `--date --start_date --end_date` | `surfosm.raw_surfosm_inventory` |
| surfosm_order.py | Surfosm orders | 31 days | `--ALL/--all --yesterday --date --start_date --end_date --output` (unused) | `surfosm.raw_surfosm_order` |
| surfosm_order_return.py | Surfosm returns | 31 days | `--yesterday --date --start_date --end_date --output` (unused) | `surfosm.raw_surfosm_order_return` |
| tiktok_vn_ads.py, tiktok_vn_ad_group.py, tiktok_vn_campaign.py | TikTok `/ad/get/`, `/adgroup/get/`, `/campaign/get/` | All objects | `--start-date --end-date --list` | `raw_tiktok.raw_tiktok_{ads,ad_group,campaign}` |
| tiktok_thai_ads.py, tiktok_thai_ad_group.py, tiktok_thai_campaign.py | same, Thai account | All objects | same | `raw_tiktok.raw_tiktok_thai_{ads,ad_group,campaign}` |
| tiktok_vn_gmv_max.py, tiktok_vn_reporting_basic_auction_ad.py | GMV max / integrated report | VN yesterday, 30-day chunks | same | `raw_tiktok.raw_tiktok_gmv_max_report`, `raw_tiktok.raw_tiktok_reporting_basic_auction_ad` |
| tiktok_thai_gmv_max.py, tiktok_thai_reporting_basic_auction_ad.py | same, Thai account | VN yesterday | same | `raw_tiktok.raw_tiktok_thai_gmv_max_report`, `raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad` |

Local credentials: same names as Cloud Run except Meta uses `META_ACCESS_TOKEN_LOCAL` and TikTok uses
`TIKTOK_ACCESS_TOKEN`. Most TikTok local scripts don't load the repo-root `.env`; export it in the shell
(`set -a; source .env; set +a`).

## CSV exporters: `src/csv_export/`

None write to BigQuery (`--project-id`/`--csv-only` flags are parsed but unused). All call the source
API (except the Taobao/Tmall Excel converter) and write CSVs to **hardcoded paths**: a macOS Google
Drive folder (`…/GoogleDrive-…/My Drive/03. CODE & DOCUMENTS/data_export_csv`) unless marked **G:**
(Windows `G:/My Drive/…`).

| File | Source | Default window |
|---|---|---|
| CSV_V1_data_export_variations.py | Pancake product variations | VN yesterday |
| CSV_V1_data_export_warehouse_transfer.py | Pancake transfers (**G:**) | VN yesterday |
| CSV_V1_manual_data_export_customer.py | Pancake customers | Yesterday (local clock) |
| CSV_V1_manual_data_export_ecom_product.py | Pancake marketplace products | Yesterday (local clock) |
| CSV_V1_manual_data_export_order.py | Pancake orders (**G:**) | Last 30 days |
| CSV_V1_manual_data_export_orders_returned.py | Pancake returned orders | VN yesterday |
| CSV_V1_manual_data_export_product.py | Pancake products | Yesterday (local clock) |
| CSV_V1_manual_data_export_product_variation.py | Pancake product variations | Yesterday (local clock) |
| CSV_V1_manual_data_export_purchase.py | Pancake purchases (**g:** `…/lsoul_document/…`) | Yesterday (local clock) |
| CSV_V1_manual_data_export_stats_inventory_product.py | Pancake inventory by product | Yesterday (local clock) |
| CSV_V1_manual_data_export_stats_inventory_variations.py | Pancake inventory analytics | Yesterday (local clock) |
| CSV_V1_manual_data_export_stats_order.py | Pancake sales analytics | VN yesterday |
| CSV_V1_manual_data_export_stats_product.py | Pancake inventory by product | VN yesterday |
| CSV_V1_manual_data_export_transaction.py | Pancake transactions | Yesterday (local clock) |
| CSV_V1_manual_dianplus-inventory.py | Dianplus inventory | Full snapshot |
| CSV_V1_manual_dianplus-order.py | Dianplus orders | 14 days |
| CSV_V1_manual_dianplus-order_refund.py | Dianplus refunds | 14 days |
| CSV_V1_manual_dianplus-product.py | Dianplus SKUs | Full snapshot |
| CSV_V1_manual_jushuitan_data_export_order.py | Jushuitan orders | Prompts; default yesterday |
| CSV_V1_manual_jushuitan_taobao_tmall_order_manual.py | Excel from `<repo>/raw_data/` (**doesn't exist**; data is in `seeds/`) | n/a |
| CSV_V1_manual_magento-data_export_order.py | Magento orders | Prompts; default VN yesterday |
| CSV_V1_manual_tiktok_data_export_ads.py | TikTok ads | All objects |
| CSV_V1_manual_tiktok_data_export_ad_group.py | TikTok ad groups | All objects |
| CSV_V1_manual_tiktok_data_export_campaign.py | TikTok campaigns | All objects |
| CSV_V1_manual_tiktok_data_export_reporting_basic_auction_ad.py | TikTok integrated report | VN yesterday |
| CSV_V1_manual_tiktok_data_export_reporting_basic_auction_ad_thai.py | TikTok integrated report (Thai) | VN yesterday |
| CSV_V1_meta_ads_data_export_ads_insight | Meta insights (no `.py` extension; runs at import) | **All time** |
| CSV_V1_surfosm_data_export_order.py | Surfosm orders (**G:**) | 31 days |
| CSV_V1_surfosm_data_export_return.py | Surfosm returns | 31 days |
| CSV_V2_manual_data_export_ecom_product.py | Pancake marketplace products | VN yesterday |
| CSV_V2_manual_data_export_product_variation.py | Pancake product variations | VN yesterday |

## Schema scripts: `src/schema/`

⚠ **Destructive.** Each script creates the dataset if missing, then **deletes the table if it exists**
and recreates it (DAY partitioning on ingestion time, `require_partition_filter=True`). With `--csv` it
then loads `CSV_PATH` with `WRITE_TRUNCATE`. Most `CSV_PATH` values are incomplete local paths.

| File | Creates | `--csv` |
|---|---|---|
| bq-raw_dianplus..inventory.py | `dianplus.raw_dianplus_inventory` | no |
| bq-raw_dianplus..order.py | `dianplus.raw_dianplus_order` | no |
| bq-raw_dianplus..order_return.py | `dianplus.raw_dianplus_order_return` (loaders write `raw_dianplus_order_refund`) | no |
| bq-raw_dianplus..product.py | `dianplus.raw_dianplus_product` | no |
| bq-raw_jushuitan..inventory.py | `jushuitan.raw_jushuitan_inventory` | no |
| bq-raw_jushuitan..order.py | `jushuitan.raw_jushuitan_order` | no |
| create_schema_bigquery_template.py | `jushuitan.raw_jushuitan_taobao_tmall_order_manual` | no |
| bq-raw_magento..order.py | `magento.raw_magento_order` | no |
| bq-raw_meta_ads_reporting_a.py | `raw_meta.raw_ads_reporting_a` | no |
| bq-raw_pancake..raw_customer.py | `raw_pancake.raw_customer` | yes |
| bq-raw_pancake..raw_ecom_product.py | `raw_pancake.raw_ecom_product` | yes |
| bq-raw_pancake..raw_inventory_histories.py | `raw_pancake.raw_inventory_histories` | no |
| bq-raw_pancake..raw_order.py | `raw_pancake.raw_order` | yes |
| bq-raw_pancake..raw_orders_returned.py | `raw_pancake.raw_orders_returned` | no |
| bq-raw_pancake..raw_product.py | `raw_pancake.raw_product` | yes |
| bq-raw_pancake..raw_product_variations.py | `raw_pancake.raw_product_variations` | no |
| bq-raw_pancake..raw_purchase.py | `raw_pancake.raw_purchase` | yes |
| bq-raw_pancake..raw_stats_inventory_product.py | `raw_pancake.raw_stats_inventory_product` | yes |
| bq-raw_pancake..raw_stats_inventory_variations.py | `raw_pancake.raw_stats_inventory_variations` | yes |
| bq-raw_pancake..raw_stats_product.py | `raw_pancake.raw_stats_product` | yes |
| bq-raw_pancake..raw_transaction.py | `raw_pancake.raw_transaction` | yes |
| bq-raw_pancake..raw_warehouse_transfer_completed.py | `raw_pancake.raw_warehouse_transfers_completed` (hardcoded Windows key path) | yes |
| bq-raw_pancake..stats_order.py | `raw_pancake.raw_stats_order` | yes |
| bq-raw_variations.py | `raw_pancake.raw_variations` | yes |
| bq-raw_surfosm..order.py | `surfosm.raw_surfosm_order` | no |
| bq-raw_surfosm..order_return.py | `surfosm.raw_surfosm_order_return` | no |
| bq-raw_surfosm.inventory.py | `surfosm.raw_surfosm_inventory` | no |
| bq-raw_tiktok_ads.py | `raw_tiktok.raw_tiktok_thai_ads` (Thai, despite the name) | no |
| bq-raw_tiktok_ad_group.py | `raw_tiktok.raw_tiktok_thai_ad_group` | no |
| bq-raw_tiktok_campaign.py | `raw_tiktok.raw_tiktok_thai_campaign` | no |
| bq-raw_tiktok_gmv_max_report.py | `raw_tiktok.raw_tiktok_thai_gmv_max_report` | no |
| bq-raw_tiktok_reporting_basic_auction_ad.py | `raw_tiktok.raw_tiktok_reporting_basic_auction_ad` (VN) | no |

No schema script exists for the VN TikTok ads/ad_group/campaign/GMV tables, the Thai reporting table,
or `raw_meta.raw_ads_reporting_ecom`/`_my`; load jobs create those tables (unpartitioned) on first load.

## Downstream SQL

Raw tables feed staging → core → reporting. See [../sql/README.md](../sql/README.md) for layers and
example chains (e.g. `raw_pancake.raw_order` → `stg_pancake.stg_order` → `sp_core_order_insert` →
`core_pancake.core_order`).
