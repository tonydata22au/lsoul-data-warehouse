# Next-run monitoring runbook: Saturday 2026-11-07 and, after the cutover, Sunday 2026-11-08 (ICT)

Prepared 2026-11-06 16:40 ICT. Target day: **Saturday 2026-11-07, Asia/Ho_Chi_Minh (UTC+7)**, which is
`2026-11-06 17:00 UTC` to `2026-11-07 17:00 UTC`. Every command below is **read-only**: it lists,
describes, reads logs or runs `SELECT`s. Nothing here deploys, triggers a job, or creates alerts or
schedules. Project `marine-cycle-484213-b4`, BigQuery location `asia-southeast1`.

> **The logs you read here can contain credentials. Don't paste, export or share them unredacted.**
> - Revisions deployed before the 2026-11-06 fix print `DIANPLUS_APP_SECRET` / `JUSHUITAN_APP_SECRET` (the
>   signing "raw string") and the Jushuitan `access_token` on every run. Treat those secrets as exposed and
>   rotate them; that is an owner action, not part of this runbook.
> - On a failed request, Pancake services (all except pancake-order) and Meta services include `api_key` /
>   `access_token` in error text and 500 bodies, and Dianplus includes `appSecret` on a failed auth.
>
> Pipe log output through the redaction filter in step c.

Contract of every service and table: [raw-destination-contract.md](raw-destination-contract.md).

## Which scenario applies

| | A. No cutover or deploy (the state on 2026-11-06) | B. After a separately approved cutover and deploy |
|---|---|---|
| Where data lands | The **old** datasets: `raw_pancake`, `raw_tiktok`, `raw_meta`, `dianplus`, `jushuitan`, `magento`, `surfosm` | `raw.<same table>` |
| Dataset `raw` | Doesn't exist yet. No rows in `raw` is expected; local tests passing doesn't change live behaviour | Exists, with the 31 copied tables |
| Old tables | Keep changing as before | `last_modified_time` must stay at `T_freeze` (fenced) |
| Local fixes (2026-11-06) | **Not live.** Old behaviour applies: thai-ads may fail to boot. 10 services return 500 on empty days. A TikTok, Dianplus, Jushuitan or Magento **outage looks like a valid empty day** (200 "0 entries found" / "No data found" / `orders_fetched: 0`), and a **mid-run failure loads a partial window with 200**, which meets the PASS evidence unless you check the fetch-error lines (step c) | Live once deployed: fetch failures are non-2xx with no load, and empty days are 2xx. Surfosm orders/returns still skip failed order details (readiness blocker) |

Old dataset per live table (scenario A): `raw_pancake`: raw_customer, raw_inventory_histories, raw_order,
raw_orders_returned, raw_product_variations, raw_stats_inventory_variations, raw_stats_product.
`raw_tiktok`: the 11 `raw_tiktok_*` tables. `raw_meta`: raw_ads_reporting_a/ecom/my. `dianplus`: 4
`raw_dianplus_*`. `jushuitan`: raw_jushuitan_inventory, raw_jushuitan_taobao_tmall_order_manual.
`magento`: raw_magento_order. `surfosm`: 3 `raw_surfosm_*`.

## Scenario C: the 2026-11-06 night deploy (fixed code, current datasets)

On the night of 2026-11-06 the fixed code was deployed to the existing services
([deploy plan](../tasks/raw-dataset-deploy-plan.md)). Each service still writes its **current** dataset
(`BQ_RAW_DATASET` / `BQ_DATASET` override), so the old-dataset destinations in scenario A still apply.
What differs from scenario A on 2026-11-07:

- **Credentials now come from Secret Manager** (`tiktok_vn_access_token`, `tiktok_th_access_token`,
  `meta_access_token`, `dianplus_app_key/secret`, `jushuitan_app_key/secret`, `magento_username/password`,
  `surfosm_api_key`, `pancake_pos`). A 401/403 or "Authentication failed" at 07:00 most likely means a
  secret value is wrong. Add a corrected secret version (the next cold start reads `latest`), or roll that
  service back.
- **Fetch failures are non-2xx with no load**, except a non-success Dianplus `resultCode` / Jushuitan `code`,
  which keeps the pages so far (decision D7; search for "API error"). Any failed Surfosm order detail fails
  the run (decision D2).
- **Empty days are 2xx** in the 10 services that used to return 500.
- **Success lines carry the job ID** in every deployed service: `… rows into|to <project>.<dataset>.<table> [<job_id>]`.
- **Not deployed (old images, old behaviour):** `pancake-orders-returned`, `jushuitan-inventory`,
  `meta-raw-ads-reporting-my`.

**Rollback per service** (no data change, takes effect immediately):
`gcloud run services update-traffic <service> --region asia-southeast1 --project marine-cycle-484213-b4 --to-revisions <previous-revision>=100`.
The previous revisions are listed in [the verification record](../tasks/raw-dataset-local-verification.md#deploy-2026-11-06-night).
The previous revisions use the old images, with credentials baked in, so a rollback only works **until those
credentials are rotated**. Rotate only after the 2026-11-07 runs succeed.

## Scenario D: first runs after the cutover (Sunday 2026-11-08 onwards)

The cutover ran on 2026-11-07 ([record](../tasks/raw-dataset-local-verification.md#cutover-2026-11-07)). Scenario B's
checks apply, with these specifics:

- **Destinations:** every one of the 26 scheduled services loads `marine-cycle-484213-b4.raw.<same table>`, as
  `lsoul-ingest-runner@marine-cycle-484213-b4.iam.gserviceaccount.com` (`user_email` of the LOAD job). A LOAD job
  by `266174294882-compute@developer` or into an old dataset is MISROUTED.
- **Old tables frozen:** `sysdb.raw_cutover_freeze` holds each old table's `last_modified` at the freeze; migration
  script query 1c must still return 0 rows. A 403 `Access Denied: Dataset … <old dataset>` in a service log means a
  stray old-dataset writer was stopped by the fence (FAILED, investigate the revision's env).
- **Readers:** Dataform `ppl-pancake` (07:45) and `ppl-pancake-orders` (08:20) read `raw.*` (release compiled from
  `main` on 2026-11-07); dbt `dbt-daily-build` (08:00) runs image `lsoul-dbt:67e1539b3459`, whose sources are on
  `raw`. Check that no job after 07:00 references an old raw table:

```sql
SELECT user_email, job_type, COUNT(*) jobs
FROM `marine-cycle-484213-b4`.`region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT, UNNEST(referenced_tables) r
WHERE creation_time >= TIMESTAMP('2026-11-08 07:00:00+07')
  AND (r.dataset_id IN ('raw_pancake','raw_tiktok','raw_meta')
       OR (r.dataset_id IN ('dianplus','jushuitan','magento','surfosm') AND STARTS_WITH(r.table_id,'raw_')))
GROUP BY 1, 2;  -- expect 0 rows (ad hoc user queries excepted)
```

- **Dianplus:** a non-success API answer now fails the run with 500 ("Dianplus API error on page N"); inventory
  requests 500 rows per page. `dianplus-inventory` should load a non-empty answer on 2026-11-08.

## Known schedules (unverified)

The repository documents only two ingestion jobs, both from docstrings and **not verified live**:

| Scheduler job | Service | Schedule | Request |
|---|---|---|---|
| `pancake-insert-raw_order` | cloud-run-pancake-order | daily 07:20 ICT | `GET /` |
| `pancake-insert-raw_product_variations` | cloud-run-pancake-product_variations | daily 07:20 ICT | `GET /` |

Every other ingestion schedule is **unknown**; step a discovers it. The Dataform `ppl-*` workflows
(07:15–08:20 ICT) are **downstream SQL schedules, not ingestion**. Don't count them as service runs.

Not every raw table changes daily. Tables with no Cloud Run writer, which change only through manual or
`local_run/` loads: `raw_orders_returned`, `raw_tiktok_ad_group`, `raw_tiktok_campaign`,
`raw_tiktok_reporting_basic_auction_campaign`, `raw_tiktok_thai_ad_group`, `raw_tiktok_thai_campaign`,
`raw_ads_reporting_my`, `raw_jushuitan_inventory`, `raw_jushuitan_taobao_tmall_order_manual`. Tables only
in code (a load would **create** them): `raw_jushuitan_order`, `raw_ecom_product`, `raw_product`,
`raw_stats_inventory_product`, `raw_stats_order`, `raw_variations`, `raw_warehouse_transfers_completed`.

## Verdicts

| Verdict | Evidence required |
|---|---|
| **PASS** | A scheduler attempt (or other trigger) → the Cloud Run request returned 2xx → exactly one LOAD job finished with no `error_result`, its destination is the intended table, and `output_rows` > 0 matches the service's logged row count → the table's partition `last_modified_time` moved within the window → **no fetch-error line** in the run's logs (step c list). That last check is required in scenario A, where a partial fetch still returns 2xx |
| **VALID EMPTY** | 2xx with an empty-source message ("No data found", "0 entries found", "0 entry found…", "No data to insert.", Magento `orders_fetched: 0`), **no** LOAD job, and the source plausibly had no data for the window |
| **FAILED** | Non-2xx (including surfosm-inventory's 400), a scheduler attempt failure, a LOAD job with `error_result`, or an ERROR log. Also any run with a fetch-error line (step c), even if it returned 2xx or loaded rows: in scenario A that is a swallowed outage or a partial window. Surfosm orders/returns (both scenarios): any `Warning: Failed to fetch order` / `Warning: Invalid response` means a partial load, and "0 order details found" with those warnings is not VALID EMPTY |
| **MISROUTED** | A successful LOAD into anything other than the intended destination: an old dataset after cutover, a wrong table, or a newly created (unpartitioned) table |
| **NO INVOCATION** | No scheduler attempt and no Cloud Run request within the grace period |
| **UNVERIFIED** | Evidence is missing or inaccessible (no log access, job not found, service name unknown) |

**Grace period (provisional):** 60 minutes after the scheduled time, plus the job's retry window
(`retryConfig`). The repository has no measured runtimes. Cloud Scheduler's default HTTP
`attemptDeadline` is 3 minutes. If a run takes longer, the scheduler records `DEADLINE_EXCEEDED` while
Cloud Run keeps going. Check the Cloud Run request and the LOAD job before calling it FAILED, and watch
for a retry starting a **second concurrent run**, which means duplicate rows.

## a. Inventory schedules (expected run times)

```sh
P=marine-cycle-484213-b4
gcloud scheduler locations list --project=$P --format="value(locationId)"
# for each location returned (at least asia-southeast1):
gcloud scheduler jobs list --project=$P --location=asia-southeast1 \
  --format="table(name.basename(), schedule, timeZone, state, httpTarget.httpMethod, httpTarget.uri, attemptDeadline, retryConfig.retryCount, scheduleTime, lastAttemptTime, status.code)"
gcloud scheduler jobs describe <job> --project=$P --location=asia-southeast1 \
  --format="yaml(name, schedule, timeZone, state, scheduleTime, lastAttemptTime, status, attemptDeadline, retryConfig, httpTarget.uri, httpTarget.httpMethod, httpTarget.oidcToken.serviceAccountEmail)"
```

`scheduleTime` is the next expected run. Map each `httpTarget.uri` to a service with step b; deployed names
can differ from folder names. **Check `httpMethod`:** 27 services accept only `GET /`. A `POST` to them
returns 405 and nothing runs. Only pancake-order, pancake-product_variations and surfosm-inventory accept POST.
The field allowlist leaves out headers and bodies, which can carry secrets.

## b. Serving revision and destination configuration (safe allowlist)

```sh
gcloud run services list --project=$P --region=asia-southeast1 \
  --format="table(metadata.name, status.url, status.latestReadyRevisionName, status.traffic[0].revisionName, status.traffic[0].percent)"
# Prints only the BQ_*/project variables, never the full environment
gcloud run services describe <service> --project=$P --region=asia-southeast1 --format=json | jq '{
  service: .metadata.name,
  image: .spec.template.spec.containers[0].image,
  serving: .status.traffic,
  service_account: .spec.template.spec.serviceAccountName,
  destination_env: [.spec.template.spec.containers[0].env[]?
      | select(.name | test("^(BQ_RAW_DATASET|BQ_DATASET|BQ_TABLE|BQ_PROJECT|GCP_PROJECT|GOOGLE_CLOUD_PROJECT)$"))
      | {name, value}]}'
```

Expected in scenario A: no `BQ_RAW_DATASET` (the old code has hardcoded old datasets). Expected in
scenario B: the new image, with `BQ_RAW_DATASET` unset or `raw`. **magento-order and surfosm-inventory
ignore `BQ_RAW_DATASET`**: their `BQ_DATASET` must be unset or `raw`.

## c. Correlate scheduler → request → fetch → load (Logs Explorer)

Times are UTC. 07:20 ICT is 00:20 UTC on 2026-11-07.

```text
# Scheduler attempts for one job
resource.type="cloud_scheduler_job" AND resource.labels.job_id="pancake-insert-raw_order"
timestamp>="2026-11-06T23:00:00Z" AND timestamp<"2026-11-07T17:00:00Z"

# Cloud Run requests (status, latency, revision, trace)
resource.type="cloud_run_revision" AND resource.labels.service_name="<service>"
logName:"run.googleapis.com%2Frequests"
timestamp>="2026-11-06T23:00:00Z" AND timestamp<"2026-11-07T17:00:00Z"

# Application lines: fetch progress, row counts, destination and job ID, errors
resource.type="cloud_run_revision" AND resource.labels.service_name="<service>"
(textPayload:("Successfully loaded" OR "Loaded " OR "Inserted " OR "Fetched" OR "entries found" OR "entry found" OR "No data" OR "records returned" OR "order details found")
 OR jsonPayload.message:("Successfully loaded" OR "Fetched") OR severity>=ERROR)

# Fetch-error lines. Most are plain prints (not ERROR severity), so search them by text.
# Any hit means the run failed or loaded a partial window, whatever its HTTP status.
resource.type="cloud_run_revision" AND resource.labels.service_name="<service>"
textPayload:("Request failed" OR "API error" OR "Error fetching data" OR "Request error" OR "Failed to fetch page"
 OR "Giving up on page" OR "Failed to fetch all orders" OR "Failed to fetch order" OR "Invalid response for order"
 OR "Failed to parse order" OR "Authentication failed" OR "Authentication request failed"
 OR "Authentication API error" OR "Traceback")
```

```sh
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="<service>" AND timestamp>="2026-11-06T23:00:00Z" AND timestamp<"2026-11-07T17:00:00Z"' \
  --project=$P --limit=300 --format="table(timestamp, resource.labels.revision_name, httpRequest.status, severity, textPayload, jsonPayload.message)" \
  | sed -E 's/(api_key|access_token|appSecret|app_secret|app_key|appId|app_id|Token|token|sign)([=:" ]+)[^&" ,}]+/\1\2***/g; s/Raw string before MD5 encryption: .*/Raw string before MD5 encryption: ***/'
```

The `sed` pipe masks credential values and old revisions' signing raw strings. Use it for every log
export.

Join the request's `trace` with its app lines. Pancake (13) and Meta (2) services already log
`… rows to <dataset>.<table> [<job_id>]` on revisions deployed before 2026-11-06. The other 15 services log the
job ID only **after** the 2026-11-06 code is deployed. For those, match LOAD jobs by destination, service
account and time (step d).

## d. BigQuery LOAD jobs (region asia-southeast1)

```sql
-- Every LOAD (and any other write) into a raw table during the target day
SELECT creation_time, DATETIME(creation_time, 'Asia/Ho_Chi_Minh') AS created_ict, start_time, end_time,
       job_type, statement_type, state, user_email, job_id,
       CONCAT(destination_table.project_id, '.', destination_table.dataset_id, '.', destination_table.table_id) AS destination,
       error_result.reason AS error_reason, error_result.message AS error_message
FROM `marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP('2026-11-06 23:00:00+00') AND creation_time < TIMESTAMP('2026-11-07 17:00:00+00')
  AND (destination_table.dataset_id IN ('raw', 'raw_pancake', 'raw_tiktok', 'raw_meta', 'dianplus', 'jushuitan', 'magento', 'surfosm')
       AND STARTS_WITH(destination_table.table_id, 'raw_'))
ORDER BY creation_time;
```

```sh
# Output rows aren't in the JOBS view for loads; read them per job:
bq --project_id=$P --location=asia-southeast1 show --format=prettyjson -j <job_id> \
  | jq '{state: .status.state, error: .status.errorResult, rows: .statistics.load.outputRows, dest: .configuration.load.destinationTable}'
```

The services write only with load jobs (`load_table_from_dataframe`). Writes by any other means are
unexpected: `QUERY` jobs with `statement_type` INSERT/MERGE/CREATE_TABLE_AS_SELECT, or `COPY` jobs (the
migration). The query above lists them too. No service uses streaming inserts. To rule them out, check
`marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.STREAMING_TIMELINE_BY_PROJECT` for
the same window.

## e. Freshness and row counts

Raw tables use **ingestion-time** DAY partitions on the UTC load date: a load at 07:20 ICT (00:20 UTC)
lands in partition `20261107`, but a load before 07:00 ICT lands in `20261106`. Source event dates
(`updated_at`, `inserted_at`, `stat_time_day`) are separate columns. Don't mix the two.

```sql
-- Partition freshness (metadata; no partition filter needed). Scenario A: run per old dataset.
SELECT table_name, partition_id, total_rows, last_modified_time,
       DATETIME(last_modified_time, 'Asia/Ho_Chi_Minh') AS last_modified_ict
FROM `marine-cycle-484213-b4.raw.INFORMATION_SCHEMA.PARTITIONS`
WHERE partition_id IN ('20261106', '20261107') OR partition_id IS NULL  -- NULL = an unpartitioned table
ORDER BY table_name, partition_id;

-- Rows loaded per UTC load date for one table (partition filter required)
SELECT DATE(_PARTITIONTIME) AS load_date_utc, COUNT(*) AS row_count
FROM `marine-cycle-484213-b4.raw.raw_order`
WHERE _PARTITIONTIME >= TIMESTAMP('2026-11-06') AND _PARTITIONTIME < TIMESTAMP('2026-11-08')
GROUP BY load_date_utc ORDER BY load_date_utc;
```

Add `--maximum_bytes_billed=1000000000` to ad-hoc `bq query` runs.

## f. Old destinations, unexpected tables, failed or partial loads, duplicates

```sql
-- Scenario B: any write to an old raw table after the cutover time (expect none; the fence should deny it)
SELECT creation_time, job_id, user_email, state, error_result.reason,
       CONCAT(destination_table.dataset_id, '.', destination_table.table_id) AS destination
FROM `marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP('<cutover time UTC>')
  AND destination_table.dataset_id IN ('raw_pancake', 'raw_tiktok', 'raw_meta', 'dianplus', 'jushuitan', 'magento', 'surfosm')
  AND STARTS_WITH(destination_table.table_id, 'raw_');

-- Tables created in raw after the copy (a writer hit a missing table) and whether they're partitioned
SELECT table_name, creation_time,
       REGEXP_CONTAINS(ddl, r'PARTITION BY') AS partitioned,
       REGEXP_CONTAINS(ddl, r'require_partition_filter\s*=\s*true') AS requires_partition_filter
FROM `marine-cycle-484213-b4.raw.INFORMATION_SCHEMA.TABLES`
WHERE creation_time >= TIMESTAMP('2026-11-06 23:00:00+00');

-- More than one successful load into the same table in the day: possible retry duplicates
SELECT CONCAT(destination_table.dataset_id, '.', destination_table.table_id) AS destination,
       COUNT(*) AS successful_loads, MIN(creation_time) AS first_load, MAX(creation_time) AS last_load
FROM `marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP('2026-11-06 23:00:00+00') AND creation_time < TIMESTAMP('2026-11-07 17:00:00+00')
  AND job_type = 'LOAD' AND state = 'DONE' AND error_result IS NULL
  AND STARTS_WITH(destination_table.table_id, 'raw_')
GROUP BY destination HAVING COUNT(*) > 1;
```

Duplicates aren't wrong in themselves: these are append-only loads with overlapping windows, and core
deduplicates. They matter when one scheduled run produced two loads (retry or concurrent run). Compare
with the scheduler attempts from step c.

## g. Reconcile fetched, transformed and loaded counts

From the app lines (step c): pages fetched and `Total rows fetched` / `Fetched … entries`, then
`Processed N rows` where logged, then `N rows into … [<job_id>]`, then the job's `outputRows` (step d),
then the partition row delta (step e). Expected differences come from the transforms: Pancake orders and
Surfosm orders explode items into rows (rows > orders), and Dianplus refunds explode return items.
**An HTTP 200, a successful scheduler attempt, or a new partition does not alone prove a complete load.**
Each step above needs its own evidence.

## h. Valid zero-row runs vs failures

VALID EMPTY means 2xx, an empty-source message, and no LOAD job. Scenario A: ten services (pancake
ecom-product, order_returned, product, stats_inventory_product, stats_inventory_variations, stats_order,
stats_product, variations, tiktok-ads, tiktok-thai-ads) still return **500 "cannot unpack non-iterable
NoneType"** on an empty day. Classify that as VALID EMPTY only if the preceding log line is "0 entr… found".
In scenario A, TikTok, Dianplus, Jushuitan and Magento also return a 2xx empty message ("0 entries found",
"No data found", `orders_fetched: 0`) when the API **failed**. Accept VALID EMPTY only when step c's
fetch-error search finds nothing for that run. In scenario B both cases are fixed. Surfosm order/order_return
(both scenarios) can load a partial set while logging `Warning: Failed to fetch order` /
`Warning: Invalid response for order`, or report "0 order details found" when every detail failed
(readiness blocker). Count those warnings: any warning means not VALID EMPTY and not PASS.

## Per-service tracking sheet

Fill one row per scheduled or observed run. Start with the two documented jobs; add every job found in step a.

| Service | Scheduled time (ICT) | Observed invocation (scheduler attempt / request time, status) | Revision | Fetch outcome / count | BigQuery job ID | Destination | Loaded rows | Freshness evidence | Verdict | Next action |
|---|---|---|---|---|---|---|---|---|---|---|
| cloud-run-pancake-order | 07:20 (documented, unverified) | | | | | A: `raw_pancake.raw_order` / B: `raw.raw_order` | | | | |
| cloud-run-pancake-product_variations | 07:20 (documented, unverified) | | | | | A: `raw_pancake.raw_product_variations` / B: `raw.raw_product_variations` | | | | |
| <each job from step a> | | | | | | | | | | |

Escalate any **MISROUTED**, any write to an old table after cutover, any unexpected new table in `raw`,
and any **FAILED** run with no successful retry.
