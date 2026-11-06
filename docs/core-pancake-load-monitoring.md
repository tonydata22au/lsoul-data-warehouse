# Runbook: check the scheduled dbt load of core.core_pancake__* (read-only)

For the run on **Saturday 2026-11-07, 08:00 Asia/Ho_Chi_Minh** (and any later day: change the date).
Evidence behind every value here: [tasks/core-pancake-schedule-map.md](../tasks/core-pancake-schedule-map.md).

**What this proves and what it doesn't.** The scheduled job runs lsoul_dbt commit `4f7c66407258`. It does not
include the uncommitted repoint fixes (variations `images`, orders_returned history, the raw-dataset rename).
A PASS here means the *deployed* models loaded tomorrow's eligible source data correctly. It says nothing about
the candidate code, which is validated separately ([T7 report](../tasks/core-pancake-repoint-t7-report.md)).

Everything below only reads: `bq query` SELECTs with `--maximum_bytes_billed`, and `gcloud … describe/list` and
`gcloud logging read`. It doesn't trigger the job, change the schedule or write to BigQuery. Run it from the
repo root as an account with BigQuery read access, JOBS_BY_PROJECT access and `run.viewer`/`logging.viewer`
(the 2026-11-06 checks used `ops.data@lsoul.com`).

## Timeline (ICT)

| Time | What happens | Source |
|---|---|---|
| 07:00–07:12 | Pancake raw loaders (order, orders_returned, inventory_histories, product_variations, customer, stats) | Cloud Scheduler `pancake-insert-*` |
| ≈07:20 | Last raw partition lands (2026-11-06: 00:20Z) | `raw_pancake.INFORMATION_SCHEMA.PARTITIONS` |
| **08:00** | `dbt-daily-build-trigger` starts Cloud Run Job `dbt-daily-build` | trigger `0 8 * * *` Asia/Saigon |
| ≈08:03 | Run normally done (2:10–2:40 in the last 8 executions) | executions list |
| 09:00–09:10 | Latest possible end: 3,600 s task timeout plus up to 2 start retries (≤ 300 s backoff each) | job and trigger config |

**Check at 08:30 ICT.** That's 27 minutes after a typical finish, enough for late log ingestion and the
INFORMATION_SCHEMA.JOBS lag (a few minutes). If the execution has no `completionTime` yet, run the post check again
at **09:15 ICT**, after the worst-case end. If it is still running then, the run has exceeded its timeout: treat it as FAIL.

## 1. Baseline (any time before 08:00 on 2026-11-07; tonight is fine)

Only the dbt job writes `core.core_pancake__*`, so the state after today's run is tomorrow's pre-run state.

```bash
OUT=data/monitoring/core_pancake/2026-11-07      # JSON output is ignored by .gitignore (*.json)
python3 scripts/monitor_core_pancake_load.py baseline --out "$OUT"
```

Saves `$OUT/baseline.json`: per table, row count, distinct keys, null keys, newest business timestamp, last modified,
and the dbt watermark (`dbt_meta.incremental_watermark`). Counts only.
Forgot it? Rebuild it with time travel (≤ 7 days): `… baseline --as-of '2026-11-07 00:59:00' --out "$OUT"`.
See the known limits on time-travel row counts below.

## 2. Post-run check (08:30 ICT)

```bash
python3 scripts/monitor_core_pancake_load.py post --run-date 2026-11-07 \
  --baseline "$OUT/baseline.json" --expected-commit 4f7c66407258 --out "$OUT"
```

Exit 0 = `PASS` or `Run succeeded; no eligible source changes`; exit 1 = anything else. A failed execution or a
dbt summary with ERROR or SKIP > 0 makes the whole verdict FAIL. When several executions exist that day, the one
created between 07:55 and 09:30 ICT (the scheduled start and its retries) is checked first. `$OUT/post_2026-11-07.json`
holds every layer's evidence. The layers are independent; a table is PASS only if all of them hold:

| Layer | Question | Evidence | Not enough on its own |
|---|---|---|---|
| L1 | Did the scheduler launch the run? | trigger `state`, `lastAttemptTime`; an execution of `dbt-daily-build` created on the date | a trigger attempt without an execution |
| L2 | Right revision, target, selection? | first log line `lsoul-dbt GIT_COMMIT=… target=prod … args: build --selector daily`; image tag | an image tag without the log line |
| L3 | Did dbt succeed for each model? | `OK created … core.core_pancake__<m>` per model and `Done. … ERROR=0 SKIP=0` | job "succeeded" (dbt warnings and skips still exit 0) |
| L4 | Were the tables actually written? | INFORMATION_SCHEMA.JOBS_BY_PROJECT: jobs by `dbt-runner@…` with destination `core.core_pancake__*`, DML statistics, no errors | table `last_modified` (a no-op MERGE also touches it) |
| L5 | Did eligible source changes arrive? | raw partitions the run newly read (watermark before → after). Per model: eligible stage keys present in core, newest stage value = core value (order/order_item/customer/variations `updated_at`, variation_warehouses `actual_remain_qty`), no new duplicate keys, no new NULL keys, no row loss (except orders_returned, which replaces by date) | a larger row count or a newer business timestamp |

Table status: `PASS`; `NO_ELIGIBLE_CHANGES` (the run succeeded, but the watermark didn't move or the window held no rows);
`FAIL`; `UNKNOWN` (any evidence missing, e.g. no execution yet, no BigQuery write record, a query error). Overall verdict:
any FAIL → FAIL; else any UNKNOWN → UNKNOWN; else any PASS → PASS; else `Run succeeded; no eligible source changes`.
**UNKNOWN is not PASS.**

Example: on 2026-11-06 `raw_product_variations` got no partition (loader log: "Successfully fetched 0 variations").
`product`, `variations` and `variation_warehouses` were correctly `NO_ELIGIBLE_CHANGES`; the other 7 passed
(order 504 eligible keys, order_item 1,330, customer 319, warehouse 11, inventory_histories 13,403, stats 4,505,
orders_returned 108; 0 missing, 0 mismatched).

## 3. Where to look by hand

```bash
# L1: trigger and executions
gcloud scheduler jobs describe dbt-daily-build-trigger --location=asia-southeast1 --format='yaml(state,schedule,timeZone,lastAttemptTime,scheduleTime,status)'
gcloud run jobs executions list --job=dbt-daily-build --region=asia-southeast1 --limit=5
# L2/L3: the execution's log (replace the name)
gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="dbt-daily-build" AND labels."run.googleapis.com/execution_name"="dbt-daily-build-XXXXX"' --order=asc --limit=400 --format='value(textPayload)' | grep -E 'GIT_COMMIT|core_pancake__|Done\.|ERROR|WARN'
# Upstream: did each raw loader write a partition today?
bq query --use_legacy_sql=false --location=asia-southeast1 "SELECT table_name, partition_id, total_rows, last_modified_time FROM \`marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.PARTITIONS\` WHERE partition_id >= '20261106' ORDER BY 1,2"
# A loader that wrote nothing: its log says how many rows the API returned
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="pancake-product-variations" AND textPayload:"fetched"' --freshness=1d --format='value(timestamp,textPayload)'
```

Cloud Console: Cloud Run → Jobs → `dbt-daily-build` → Executions; Cloud Scheduler → `dbt-daily-build-trigger`.
Alerts for a failed execution go to `ops.data@lsoul.com` (lsoul_dbt `deploy/alert-policy*.json`).

## Interpreting results

- **FAIL with `missing` > 0:** eligible stage keys aren't in core. Check L3 for that model, then the model's window
  (`dbt_meta.incremental_watermark`).
- **FAIL with `mismatched` > 0:** core holds an older value than the newest stage row. Look for a late raw partition
  that landed after the run's watermark lookup (a known limit of `lsoul_record_watermark`), and check the next run.
- **NO_ELIGIBLE_CHANGES for the variations family:** check the loader log. "Fetched 0" is a legitimately empty day;
  an HTTP error is an ingestion incident (docs/troubleshooting.md).
- **UNKNOWN at 08:30:** usually the run isn't finished or JOBS hasn't caught up. Re-run at 09:15.

## Known limits

- Source checks use the **deployed** staging views (`stage.stg_pancake__*`, the model's actual input). They don't
  re-derive staging from raw.
- `warehouse`, `inventory_histories` and `product` are checked for key presence only. `stats_inventory_variations`
  is compared on distinct stage rows against target rows for the load day (the model is a SELECT DISTINCT append),
  and `orders_returned` on per-day counts of the newest load's 28-day window.
- **Time-travel row counts didn't reconcile** with JOBS DML statistics on 2026-11-06. For example,
  `stats_inventory_variations` already showed the 4,505 rows dated 11-06 at 2026-11-05 20:00Z, but JOBS records
  their MERGE at 2026-11-06 01:01:49Z, and no other job in the project touched the table. Prefer a live baseline,
  taken before 08:00, over `--as-of`.
- A raw partition landing during the run can move the watermark past rows the run didn't read
  (lsoul_dbt `macros/incremental/watermark.sql`). The next day's reconciliation window covers it.
