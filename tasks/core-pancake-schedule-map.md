# Verified schedule, dependency map and per-table checklist: core.core_pancake__*

Read-only evidence gathered 2026-11-06 (Asia/Ho_Chi_Minh), @thread:thr_fzwqdp2wyw. Runbook for the
2026-11-07 load: [docs/core-pancake-load-monitoring.md](../docs/core-pancake-load-monitoring.md).

## Scheduled dbt job (live, `gcloud … describe`)

| Item | Live value | Note |
|---|---|---|
| Trigger | Cloud Scheduler `dbt-daily-build-trigger`, asia-southeast1 | **ENABLED** (the repo docs still say "created paused") |
| Cron / time zone | `0 8 * * *`, `Asia/Saigon` = 08:00 ICT | `lsoul_dbt/deploy/README.md` still says 09:00. Retry: 2 attempts, backoff 60–300 s |
| Next run | `2026-11-07T01:00:00Z` = **Sat 2026-11-07 08:00 ICT** | `scheduleTime` |
| Job | Cloud Run Job `dbt-daily-build` | 1 task, `--max-retries=0`, `timeoutSeconds=3600` |
| Image | `…/lsoul-dbt/lsoul-dbt:4f7c66407258` (`GIT_COMMIT=4f7c66407258`) | lsoul_dbt commit 4f7c664 (2026-11-05 15:19 +07), **7 commits behind HEAD**, and every local edit is uncommitted |
| Command | no args → `entrypoint.sh`: `dbt source freshness` (non-fatal), then `dbt build --selector daily` | First log line: `lsoul-dbt GIT_COMMIT=4f7c66407258 target=prod … args: build --selector daily` |
| Target | `LSOUL_DBT_TARGET=prod`, threads 4 | |
| Selector `daily` | `models/` + `seeds/` minus tag `unscheduled` | At 4f7c664 no Pancake model carries `unscheduled` (git grep) |
| Last run | `dbt-daily-build-bbs67`, 2026-11-06 01:00:04–01:02:41Z, succeeded | `PASS=130 WARN=0 ERROR=0 SKIP=0`; all 10 `core_pancake__*` models `OK` |
| Typical duration | 2 min 10 s – 2 min 40 s (8 executions, 2026-11-04 … 11-06) | One failure (2026-11-05 02:00Z, image 1e03acb6) before the schedule moved to 08:00 |

**The deployed job runs commit 4f7c664**, which has none of the local changes (images, orders_returned history,
raw-dataset rename). Between 4f7c664 and HEAD only `dbt_project.yml` changed among Pancake-relevant files.
**Tomorrow's run validates only the deployed tables' freshness, not the local fixes.**

## Upstream loaders (Cloud Scheduler → Cloud Run services, all ENABLED, `Asia/Saigon`)

| Raw table (`raw_pancake`) | Trigger | Time (ICT) | Recent partitions (rows) |
|---|---|---|---|
| raw_order | `pancake-insert-raw_order` | 07:00 | 11-02…11-06: 617 / 1,204 / 965 / 980 / 1,330 |
| raw_orders_returned | `pancake-insert-raw_orders_returned` → service `pancake-orders-returned` | 07:00 | daily since at least 10-25; 11-06: 108. **Has an active loader** (the service was deployed from source 2026-03-01; no repo folder matches it). The dbt source note "loaded only by the local script" is out of date |
| raw_inventory_histories | `pancake-insert-inventory_histories` | 07:05 | 11-06: 13,403 |
| raw_product_variations | `pancake-insert-raw_product_variations` | 07:05 | **no 2026-11-06 partition**: the loader ran and logged "Successfully fetched 0 variations … No data to export". dbt freshness: WARN |
| raw_customer | `pancake-insert_raw_customer` | 07:10 | 11-06: 319 |
| raw_stats_inventory_variations | `pancake-insert_raw_stats_inventory_variations` | 07:12 | 11-06: 4,505 |

Raw partitions are UTC ingestion dates. A load at 07:00 ICT on 2026-11-07 lands in partition `20261107`.
On 2026-11-06 the last load finished at 00:20Z (07:20 ICT), 40 minutes before dbt.

Legacy writers of the **old** tables keep running and don't touch `core.*`: Dataform `ppl-pancake/ppl_pancake_product`
07:45 ICT (also runs the sale-end UPDATE) and `ppl-pancake-orders/ppl_pancake_orders` 08:20 ICT; `ppl-reports` 08:40.

## Lineage (dbt manifest `lsoul_dbt/target/manifest.json`, parsed 2026-11-06; reader counts from `sql/`)

| Core model | dbt parents | Raw source (live today) | Repo routines reading it after the repoint |
|---|---|---|---|
| core_pancake__order | stg_pancake__order | raw_order | 16 |
| core_pancake__order_item | stg_pancake__order | raw_order | 17 |
| core_pancake__orders_returned | stg_pancake__orders_returned, stg_pancake__orders_returned_history | raw_orders_returned + frozen history (not created) | 15 |
| core_pancake__customer | stg_pancake__customer | raw_customer | 0 |
| core_pancake__product | stg_pancake__product, seed pancake_sale_end_display_ids | raw_product_variations | 30 |
| core_pancake__variations | stg_pancake__variations | raw_product_variations | 26 |
| core_pancake__variation_warehouses | stg_pancake__variation_warehouses | raw_product_variations | 3 |
| core_pancake__warehouse | stg_pancake__inventory_histories, core_pancake__inventory_histories | raw_inventory_histories | 38 |
| core_pancake__inventory_histories | stg_pancake__inventory_histories | raw_inventory_histories | 2 |
| core_pancake__stats_inventory_variations | stg_pancake__stats_inventory_variations | raw_stats_inventory_variations | 0 |

Scheduled consumers of the reportdb readers: scheduled queries `sp_sales_performance_dashboard_daily` and
`sp_stock_inventory_dashboard_daily` (02:00, snapshot), Dataform `ppl-reports` 08:40, Looker Studio (listed by hand
in `lsoul_dbt/data-lineage/looker/reports.yml`). **Today no live routine reads `core.core_pancake__*`** (0 of 70 reportdb
routines; 39 read `core_pancake.core_*`). The new tables have no production consumers until the repoint is deployed.

Graphify: `lsoul_dbt/graphify-out/graph.json` (built 2026-11-05 17:45) has the dbt model files as nodes with
**degree 0**: it holds no `ref()`/`source()` edges, and `graphify path stg_… core_…` finds no path. The edges above come
from the dbt manifest and a grep of `sql/`, not from Graphify. `lsoul-data-warehouse` has no graph; none was built.

## Per-table checklist

Grain/key = the model's dbt uniqueness test. "Load field" = the raw `_PARTITIONTIME` exposed as `load_time` in staging,
tracked per model in `dbt_meta.incremental_watermark.source_partition_time`. No core table has a `loaded_at` column.

| Table | Grain / key | Materialization / strategy | Load field (watermark) | Business update field | Cadence | Baseline (2026-11-06 post-run) | Post-run evidence | 11-06 result |
|---|---|---|---|---|---|---|---|---|
| core_pancake__order | order_id | incremental, insert_overwrite on `inserted_at` partitions (lsoul_upsert) | raw_order load_time | updated_at (STRING), inserted_at | daily | 79,531 rows, wm 11-06 | L3 OK, L4 MERGE, L5 keys+updated_at | PASS (504 eligible) |
| core_pancake__order_item | order_id, order_item_id | incremental, insert_overwrite on `order_date` | raw_order load_time | updated_at (STRING) | daily | 159,840, wm 11-06 | same | PASS (1,330) |
| core_pancake__customer | customer_id, shop_customer_addresses_id | incremental merge (replace) on `updated_at` | raw_customer load_time | updated_at | daily | 47,117, wm 11-06 | same | PASS (319) |
| core_pancake__product | raw_product_id | incremental merge, unique_key raw_product_id | raw_product_variations load_time | updated_at | daily, when variations change | 4,463, wm 11-05 | presence of keys | NO_ELIGIBLE_CHANGES (loader got 0 rows) |
| core_pancake__variations | variation_id | incremental merge, unique_key variation_id | raw_product_variations | updated_at | same | 4,467, wm 11-05 | keys + updated_at | NO_ELIGIBLE_CHANGES |
| core_pancake__variation_warehouses | variation_id, warehouse_id | incremental merge (replace) | raw_product_variations | updated_at | same | 22,603 (1,532 rows with a NULL key part, pre-existing), wm 11-05 | keys + actual_remain_qty | NO_ELIGIBLE_CHANGES |
| core_pancake__warehouse | warehouse_id | incremental merge, unique_key warehouse_id (+ policy UPDATEs) | raw_inventory_histories | updated_at | daily | 19, wm 11-06 | key presence | PASS (11) |
| core_pancake__inventory_histories | inventory_history_id, inv_warehouse_id | incremental insert_overwrite on `inserted_at` | raw_inventory_histories | inserted_at | daily | 3,910,254, wm 11-06 | key presence | PASS (13,403) |
| core_pancake__stats_inventory_variations | none (append) | incremental merge (append), `inserted_at` = TIMESTAMP_TRUNC(proc_date, DAY) | raw_stats_inventory_variations | inserted_at | daily | 1,103,224, wm 11-06 | distinct stage rows = target rows for the load day | PASS (4,505) |
| core_pancake__orders_returned | none (replace by inserted_at date; duplicates flagged) | incremental merge + pre-hook DELETE of the 28-day window | raw_orders_returned | inserted_at | daily | 936 (deployed model has no history), wm 11-06 | per-day counts of the newest load = target | PASS (108) |

The 11-06 column is the monitor's own run against this morning's execution (time-travel baseline as of
2026-11-06 00:59Z). Its row counts are unreliable; see "Known limits" in the runbook.

Not in the daily job: no Pancake model is tagged `unscheduled`, and there are no manual-only Pancake models.
**Source without an active loader:** `raw.raw_orders_returned_history` (planned, not created; the dataset `raw` doesn't
exist yet). All six live raw Pancake sources have enabled loaders.
