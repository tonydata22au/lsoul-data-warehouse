# Raw destination contract: every Cloud Run service and the table it writes

Status (2026-11-06): **local working tree only, not deployed.** It describes the code in `src/cloud_run/`
after the raw-dataset consolidation ([plan](../tasks/raw-dataset-plan.md)). The live services keep their
current destinations until a separately approved cutover and deploy. Verified offline, with mocks, by
`tests/test_cloud_run_destinations.py`, `tests/test_cloud_run_routes.py` and `tests/test_cloud_run_fetch.py`
(see [the verification record](../tasks/raw-dataset-local-verification.md)).

## Destination rule

Every service appends to `marine-cycle-484213-b4.raw.<table>`, keeping the table name it already had.
Configuration, highest precedence first:

| Services | Project | Dataset | Table |
|---|---|---|---|
| 28 standard services | runtime credentials (ADC project of the Cloud Run service account); `cloud-run-surfosm-order(_return)` routes pass `GCP_PROJECT` when set | `BQ_RAW_DATASET`, default `raw` | fixed in code |
| `cloud-run-magento-order` | `BQ_PROJECT`, default `marine-cycle-484213-b4` | `BQ_DATASET`, default `raw` | `BQ_TABLE`, default `raw_magento_order` |
| `cloud-run-surfosm-inventory` | route: `GCP_PROJECT`, then `GOOGLE_CLOUD_PROJECT`, then ADC | `BQ_DATASET`, default `raw` | `BQ_TABLE`, default `raw_surfosm_inventory` |

- The dataset default is a **function default argument** (`dataset_id=os.getenv(...)`), read once at
  import. A changed env var takes effect on the next revision or cold start, never mid-process.
- `BQ_RAW_DATASET` has **no effect** on Magento and surfosm-inventory (tested). Before a cutover, check
  their live `BQ_DATASET`. A leftover `BQ_DATASET=magento`/`surfosm` keeps them on the old dataset.
- Every load: `load_table_from_dataframe`, `WRITE_APPEND`, `ALLOW_FIELD_ADDITION` + `ALLOW_FIELD_RELAXATION`,
  all columns cast to STRING. `load_job.result()` is awaited once, and a failed job raises. Exactly one
  load job per request, after all fetching. The only Meta-specific step is `create_dataset_if_not_exists`
  (it creates `raw` in `asia-southeast1` if missing).
- A load into a table that doesn't exist **creates it** with no partitioning, the DataFrame's columns and
  no `require_partition_filter`. The schema scripts create raw tables with ingestion-time DAY
  partitioning, so copy or create every target table before switching a writer.

## Service → table

LIVE means in the live inventory read on 2026-11-05 (now in an old dataset, moving to `raw`).
CODE means the table doesn't exist live: a service that writes it has probably not run.
Line numbers are the loader's `def`, or the dataset/table constant for Magento, Meta and surfosm-inventory.

| Service (folder) | Source API → entity, account | Destination (default) | Status | Code | Local / schema variant |
|---|---|---|---|---|---|
| cloud-run-dianplus-inventory | Dianplus → inventory | `raw.raw_dianplus_inventory` | LIVE | `cr-dianplus-inventory.py:327` | `dianplus_inventory.py` / `bq-raw_dianplus..inventory.py` |
| cloud-run-dianplus-order | Dianplus → orders | `raw.raw_dianplus_order` | LIVE | `cr-dianplus-order.py:583` | `dianplus_order.py` / `bq-raw_dianplus..order.py` |
| cloud-run-dianplus-order-refund | Dianplus → refunds | `raw.raw_dianplus_order_refund` | LIVE | `cr-dianplus-order-refund.py:551` | `dianplus_order_refund.py` / `bq-raw_dianplus..order_return.py` (now names `raw_dianplus_order_refund`) |
| cloud-run-dianplus-product | Dianplus → products | `raw.raw_dianplus_product` | LIVE | `cr-dianplus-product.py:469` | `dianplus_product.py` / `bq-raw_dianplus..product.py` |
| cloud-run-jushuitan-order | Jushuitan → orders | `raw.raw_jushuitan_order` | CODE | `cr-jushuitan-order.py:690` | `jushuitan_order.py` / `bq-raw_jushuitan..order.py` |
| cloud-run-magento-order | Magento → orders | `raw.raw_magento_order` | LIVE | `cr-magento-order.py:58-60` | `magento_order.py` / `bq-raw_magento..order.py` |
| cloud-run-meta-ads-reporting-a | Meta Graph insights, account `act_785254401088992` | `raw.raw_ads_reporting_a` | LIVE | `cr-meta-ads_reporting-a.py:47-48` | `meta_ads_a.py` / `bq-raw_meta_ads_reporting_a.py` |
| cloud-run-meta-ads-reporting-ecom | Meta Graph insights, e-commerce account | `raw.raw_ads_reporting_ecom` | LIVE | `cr-meta-ads_reporting-ecom.py:49-50` | `meta_ads_ecom.py` / — |
| cloud-run-pancake-customer | Pancake → customers | `raw.raw_customer` | LIVE | `cr-pancake-customer.py:290` | `pancake_customer.py` / `bq-raw_pancake..raw_customer.py` |
| cloud-run-pancake-ecom-product | Pancake → e-commerce products | `raw.raw_ecom_product` | CODE | `cr-pancake-ecom_product.py:217` | — / `bq-raw_pancake..raw_ecom_product.py` |
| cloud-run-pancake-inventory_histories | Pancake → inventory histories | `raw.raw_inventory_histories` | LIVE | `cr-pancake-inventory_histories.py:341` | `pancake_inventory_histories.py` / `bq-raw_pancake..raw_inventory_histories.py` |
| cloud-run-pancake-order | Pancake → `/orders` | `raw.raw_order` | LIVE | `cr-pancake-order.py:591` (dataset `:91-92`) | `pancake_order.py` / `bq-raw_pancake..raw_order.py` |
| cloud-run-pancake-order_returned | Pancake → **`/orders`** (not returns, see finding 1) | `raw.raw_order` | LIVE | `cr-pancake-order.py:443` (fetch `:259`) | — (the returns pipeline is `pancake_orders_returned.py` → `raw_orders_returned`) |
| cloud-run-pancake-product | Pancake → products | `raw.raw_product` | CODE | `cr-pancake-product.py:289` | — / `bq-raw_pancake..raw_product.py` |
| cloud-run-pancake-product_variations | Pancake → product variations | `raw.raw_product_variations` | LIVE | `cr-pancake-product_variations.py:387` | `pancake_product_variations.py` / `bq-raw_pancake..raw_product_variations.py` |
| cloud-run-pancake-stats_inventory_product | Pancake → inventory stats by product | `raw.raw_stats_inventory_product` | CODE | `cr-pancake-stats_inventory_product.py:240` | — / `bq-raw_pancake..raw_stats_inventory_product.py` |
| cloud-run-pancake-stats_inventory_variations | Pancake → inventory stats by variation | `raw.raw_stats_inventory_variations` | LIVE | `cr-pancake-stats_inventory_variations.py:258` | `pancake_stats_inventory_variations.py` / `bq-raw_pancake..raw_stats_inventory_variations.py` |
| cloud-run-pancake-stats_order | Pancake → order stats | `raw.raw_stats_order` | CODE | `cr-pancake-stats_order.py:256` | — / `bq-raw_pancake..stats_order.py` |
| cloud-run-pancake-stats_product | Pancake → product stats | `raw.raw_stats_product` | LIVE | `cr-pancake-stats_product.py:221` | `pancake_stats_product.py` / `bq-raw_pancake..raw_stats_product.py` |
| cloud-run-pancake-variations | Pancake → variations | `raw.raw_variations` | CODE | `cr-pancake-variations.py:322` | — / `bq-raw_variations.py` |
| cloud-run-pancake-warehouse_transfer | Pancake → completed warehouse transfers | `raw.raw_warehouse_transfers_completed` | CODE | `cr-pancake-warehouse_transfer.py:295` | — / `bq-raw_pancake..raw_warehouse_transfer_completed.py` |
| cloud-run-surfosm-inventory | Surfosm (ScaleUp) → inventory per day | `raw.raw_surfosm_inventory` | LIVE | `cr-surfosm-inventory.py:44-45`, loader `:169` | `surfosm_inventory.py` / `bq-raw_surfosm.inventory.py` |
| cloud-run-surfosm-order | Surfosm → order list + per-order detail | `raw.raw_surfosm_order` | LIVE | `cr-surfosm-order.py:325` | `surfosm_order.py` / `bq-raw_surfosm..order.py` |
| cloud-run-surfosm-order_return | Surfosm → return list + per-return detail | `raw.raw_surfosm_order_return` | LIVE | `cr-surfosm-order_return.py:308` | `surfosm_order_return.py` / `bq-raw_surfosm..order_return.py` |
| cloud-run-tiktok-ads | TikTok ads, **VN** advertiser (`TIKTOK_VN_ACCESS_TOKEN`) | `raw.raw_tiktok_ads` | LIVE | `cr-tiktok-ads.py:188` | `tiktok_vn_ads.py` / — |
| cloud-run-tiktok-gmv-max-report | TikTok GMV Max report, **VN** | `raw.raw_tiktok_gmv_max_report` | LIVE | `cr-tiktok-gmv-max-report.py:176` | `tiktok_vn_gmv_max.py` / — |
| cloud-run-tiktok-reporting-basic-autction-ad | TikTok basic auction-ad report, **VN** | `raw.raw_tiktok_reporting_basic_auction_ad` | LIVE | `cr-tiktok-reporting-basic-auction-ad.py:292` | `tiktok_vn_reporting_basic_auction_ad.py` / `bq-raw_tiktok_reporting_basic_auction_ad.py` |
| cloud-run-tiktok-thai-ads | TikTok ads, **TH** advertiser (`TIKTOK_TH_ACCESS_TOKEN`) | `raw.raw_tiktok_thai_ads` | LIVE | `cr-tiktok-ads.py:202` (thai folder) | `tiktok_thai_ads.py` / `bq-raw_tiktok_ads.py` (creates the **thai** table) |
| cloud-run-tiktok-thai-gmv-max-report | TikTok GMV Max report, **TH** | `raw.raw_tiktok_thai_gmv_max_report` | LIVE | `cr-tiktok-thai-gmv-max-report.py:178` | `tiktok_thai_gmv_max.py` / `bq-raw_tiktok_gmv_max_report.py` (thai table) |
| cloud-run-tiktok-thai-reporting-basic-autction-ad | TikTok basic auction-ad report, **TH** | `raw.raw_tiktok_thai_reporting_basic_auction_ad` | LIVE | `cr-tiktok-thai-reporting-basic-auction-ad.py:308` | `tiktok_thai_reporting_basic_auction_ad.py` / — |

**Schedulers.** Only `pancake-insert-raw_order` → `cloud-run-pancake-order` and
`pancake-insert-raw_product_variations` → `cloud-run-pancake-product_variations` are documented: daily
07:20 ICT, `GET /` ([pipelines.md](pipelines.md)). They are taken from docstrings and not verified live.
Every other trigger is **unknown**; the runbook discovers them.

## Coverage totals

| Count | What |
|---|---|
| 30 | Cloud Run service folders, each tested |
| 29 | Distinct destination tables (`raw_order` is written by both pancake-order and pancake-order_returned) |
| 22 | of them are live tables (31 live in total) |
| 7 | are code-only, not live: `raw_jushuitan_order`, `raw_ecom_product`, `raw_product`, `raw_stats_inventory_product`, `raw_stats_order`, `raw_variations`, `raw_warehouse_transfers_completed` |
| 9 | live tables with **no Cloud Run writer**, filled only by `local_run/` or manual loads: `raw_orders_returned`, `raw_tiktok_ad_group`, `raw_tiktok_campaign`, `raw_tiktok_reporting_basic_auction_campaign` (no writer in this repo at all), `raw_tiktok_thai_ad_group`, `raw_tiktok_thai_campaign`, `raw_ads_reporting_my`, `raw_jushuitan_inventory`, `raw_jushuitan_taobao_tmall_order_manual` |

## HTTP and CLI behaviour

| Behaviour | Services |
|---|---|
| Routes | `GET /` for 27 services. `GET`/`POST /`: pancake-order, pancake-product_variations. `/`, `/run` any method + `GET /healthz`: surfosm-inventory. `GET /`, `/run`, `/healthz`: magento-order. **A scheduler job that sends POST to a GET-only route gets 405 and nothing runs.** |
| Success | 2xx, one load job, and the log line `… N rows into|to <dataset>.<table> [<job_id>]` (job ID and project added to 15 services on 2026-11-06) |
| Valid empty source | 2xx with no load job. Messages: "No data found", "No data", "0 entries found", "0 entries found. No data to export.", "0 entry found. No data to export.", "0 records returned; nothing to load." (Meta), "No data to insert." (surfosm-inventory), "0 order numbers found. No data to export." / "No data to export after flattening." (Surfosm orders/returns), Magento `{"orders_fetched": 0}`. **Not proof of an empty source** on Surfosm orders/returns ("0 order details found" can mean every detail call failed: a readiness blocker), or on any revision deployed before 2026-11-06 (see the runbook) |
| Fetch failure (connection error, HTTP 5xx, API error code, a later page failing) | non-2xx and no load job: 500 everywhere except surfosm-inventory, which answers **400** because its handler maps `ValueError` to 400. Still a failed attempt for Cloud Scheduler |
| Load failure | 500 (no rows-loaded claim). CLI: uncaught exception or exit 1 |
| CLI | `main()` in 29 services. A failure exits non-zero. Magento has no CLI: running the file starts Flask |

**Readiness blockers** (tests mark them `expectedFailure`; see `READINESS_BLOCKERS` in
`tests/test_cloud_run_fetch.py`):

| Key | Service | Behaviour | Owner decision needed |
|---|---|---|---|
| `surfosm_order_detail_skip` | cloud-run-surfosm-order | `fetch_order_details()` logs and skips any order whose detail request fails or answers `ok: false` (`cr-surfosm-order.py:196-208`), loads the rest, and reports success. If **every** detail fails it reports "0 order details found" with 200 / exit 0, which looks like a valid empty day (both pinned by `test_blocked_behaviour_is_still_exactly_the_documented_one`) | Fail the whole run, or skip with an explicit partial status and an alert? The default 31-day window re-fetches old dates, which may heal a skip but appends duplicates |
| `surfosm_order_return_detail_skip` | cloud-run-surfosm-order_return | Same (`cr-surfosm-order_return.py:170-182`) | Same decision; keep both consistent |

## Behaviour changed locally on 2026-11-06 (takes effect only after a deploy)

| Change | Services | Retry consequence |
|---|---|---|
| `app_runner.py` loads the existing `cr-tiktok-ads.py` (before: missing file, container can't boot) | tiktok-thai-ads | The service can start. It writes `raw_tiktok_thai_ads` and still needs `TIKTOK_TH_ACCESS_TOKEN` set on the live service (read at import, `cr-tiktok-ads.py:39`) |
| A failed page, request error or API error code **raises** instead of returning the rows so far | tiktok ×6, dianplus ×4, jushuitan-order, magento-order (both modes) | Before: 200 with an empty or partial load. After: 500 with **no load**, so retrying a *fetch* failure can't duplicate rows (the single load happens after all fetching). This doesn't cover a retry that starts while a slow run is still going (`attemptDeadline` exceeded), or a load that committed but whose `.result()` raised: both can still duplicate. If Dianplus (`resultCode`) or Jushuitan (`code`) ever signals end-of-data with a non-success code, those runs now fail loudly; the runbook watches for it |
| Credentials no longer printed: the signing "raw string" (it starts with `APP_SECRET`) is not printed, and `app_id`/`app_key`/`access_token`/`sign` are masked in the per-page `Request params` log | dianplus ×4, jushuitan-order | None. **Before this fix, every run wrote `DIANPLUS_APP_SECRET` / `JUSHUITAN_APP_SECRET` to Cloud Logging**, so treat both as exposed and rotate them. Guarded by `test_fetch_output_never_contains_a_credential` |
| A valid empty source returns 2xx instead of crashing (`return` → `return "<message>", 200`) | pancake-ecom-product, -order_returned, -product, -stats_inventory_product, -stats_inventory_variations, -stats_order, -stats_product, -variations, tiktok-ads, tiktok-thai-ads | Before: 500 "cannot unpack non-iterable NoneType" on every empty day, so retries and alerts on quiet days. After: VALID EMPTY. This was a documented known issue left for a decision; review before deploying |
| Success log line includes `project.dataset.table [job_id]` | 15 services (see the routes test) | None |
| `bq-raw_dianplus..order_return.py` creates `raw_dianplus_order_refund` (85 columns identical to the loaders) | schema script (never run in this task) | Before, running it created an unused table. Now it **drops and recreates the live `raw.raw_dianplus_order_refund`** (data loss), like every other schema script. Never run it against a populated table |

## Findings that stay open

1. **`cloud-run-pancake-order_returned` writes ordinary orders.** It fetches `/orders` and appends to
   `raw_order`, as a copy of pancake-order with a 30-day window and an older column set. Repointing only
   its table would put ordinary orders into `raw_orders_returned`. Pinned as-is by the tests. Owner
   decision: retire it, or port `src/local_run/pancake_orders_returned.py` (`/orders_returned` →
   `raw_orders_returned`). If deployed today alongside pancake-order, `raw_order` receives duplicates.
2. **`src/schema/bq-raw_jushuitan..order.py` has edits beyond the dataset change.** Compared with HEAD it
   also sets `REQUIRE_PARTITION_FILTER = False` (HEAD: `True`, as every live raw table requires) and drops
   the `GOOGLE_APPLICATION_CREDENTIALS` fallback (key path now `<repo>/credentials/…`, HEAD:
   `src/credentials/…` or the env var). Its origin is unknown, so it's kept. Restore the HEAD values unless
   they were intended. Not a cutover blocker: the script is never run in the cutover and `raw_jushuitan_order`
   isn't live.
3. **surfosm-inventory answers 400 for upstream failures** (it maps `ValueError` to 400). It is non-2xx, so
   the failure is surfaced, but 400 looks like a bad request in dashboards.
4. **Seven services write code-only tables.** If any of them is deployed and scheduled, its first load into
   `raw` creates an unpartitioned table. Check W1 (writer inventory) before cutover.
5. `src/local_run/` and `src/csv_export/` variants keep their old fetch-error handling and **still print
   the Dianplus/Jushuitan signing raw string (app secret)** to the operator's terminal
   (`local_run/dianplus_*.py`, `local_run/jushuitan_*.py`, `csv_export/CSV_V1_manual_dianplus-*.py`,
   `csv_export/CSV_V1_manual_jushuitan_data_export_order.py`). Only `cloud_run/` changed (AGENTS.md: note
   when variants aren't updated).
6. **Credentials can still appear in error text** (pre-existing, failure paths only). 12 Pancake services
   (every one except pancake-order, which redacts) send `api_key` as a URL query parameter, and both Meta
   services send `access_token` the same way. On a failed request the `requests` error text contains that
   URL. It is re-raised as `API request failed: {e}`, returned in the HTTP 500 body (`Error: {exc}`) and
   logged with `logging.exception`. Dianplus authenticates with `appSecret` in the URL
   (`cr-dianplus-inventory.py:78-98`), so a failed auth does the same. The harness can't detect this
   (its fake responses have no query string). Fix: port pancake-order's `redact_api_key` / `raise … from
   None` pattern to these services. Until then, treat error logs and 500 bodies as secret-bearing.
