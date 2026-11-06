# Review packet: finish the core_pancake → core repoint (T8)

Plan: [core-pancake-repoint-plan.md](core-pancake-repoint-plan.md). Tasks: [core-pancake-repoint-todo.md](core-pancake-repoint-todo.md).
Built 2026-11-05/06 in the Agent Flow Build stage (@thread:thr_34rtwqfn2y). **Nothing is deployed.**
No CREATE OR REPLACE, DML or dbt run touched BigQuery (D4). Every BigQuery call was read-only or a dry run.
Nothing is committed (both repos, branch `main`).

## Decisions for the owner

1. **T7 is not run.** Old-vs-new comparison for the 142 baseline calls (plus new objects) needs `bq`
   (read-only queries). The 2026-11-05 baseline used `bq` with approval in @thread:thr_9b2q2q7sia.
   Approve `bq` read-only for the Verify stage, or say how to compare instead.
2. **`fn_order_product_inventory_summary` is already broken live.** It calls
   `fn_china_product_inventory(1, '')`, but the live signature is `(INT64, INT64)`. A dry run of the
   live function fails today, so deploying the repointed file fails the same way. Options: deploy as
   is (no change), fix the call to `(1, 1)` (a behavior change), or leave it out of the deploy.
3. **T2 history table (D1).** The 728 pre-2026-02-11 return rows are frozen into a one-time table, not a dbt
   seed, because the rows hold customer names (no customer data in Git). The parallel raw-dataset work
   ([raw-dataset-plan.md](raw-dataset-plan.md)) has since changed its dataset from `raw_pancake` to `raw`.
   Run the freeze only after that dataset exists, or keep it in `raw_pancake`.
4. **Overlap with the raw-dataset session.** That session edits the same files (dbt sources, staging,
   `sp_stock_inventory_dashboard_daily`). Its copy of `sp_stock_inventory_dashboard_daily` was built from the
   stale 2026-10-28 snapshot, which would undo live's 2026-11-04 change. This file is now live DDL plus that
   session's two `raw.` repoints (see "Files").
5. **Sale-end seed drift (found in Verify, blocks cutover).** 54 products carry `SYS_01_SALE_END` in live
   `core_pancake.core_product` but not in `core.core_pancake__product`. None of their display IDs are in
   `lsoul_dbt/seeds/pancake/pancake_sale_end_display_ids.csv` (taken 2026-11-01); live's Dataform UPDATE list has
   grown since. Repointed readers (`fn_dim_sku.is_sale_end`, the inventory summaries) would treat them as active.
   Refresh the seed from the live Dataform operation (needs a `gcloud` read), `dbt seed`, then `--full-refresh`
   `core_pancake__product` before step 5 of the deploy.

## Expected differences after cutover (Verify, read-only, 2026-11-06)
- `variation_warehouses`: new matches the latest raw load for every difference (5,371 quantity changes,
  3,340 new pairs); the old table is stale (1,874 pairs not in raw). Total `actual_remain_qty` goes from
  89,215 to 74,773, so stock reports drop. This corrects them; it is not a loss.
- `orders_returned`: −728 rows until the T2 freeze and full refresh (then equal).
- `warehouse`: the 7 D3 policy fixes.
- `order`: 5 of 79,315 rows differ in customer snapshot columns (`customer_purchased_amount`, `customer_last_order_at`, …), load timing.
- `product`: besides the 54 sale-end flags, `product_attributes`/`supplier_product_ids` strings differ in format
  (newer raw serialization; no reader uses them), and 84 old-only products have no variations (6 have orders).
- `customer`, `order_item`, `variations` (except `images`): identical.

## Files

### lsoul-data-warehouse
| Change | Files |
|---|---|
| T1 live-only writer, equal to live (SHA-256) | `sql/procedures/core_pancake.sp_pancake_core_variations_insert.sql` |
| T2 one-time freeze (prepared, not run) | `sql/ad_hoc/q-freeze_pancake_orders_returned_history.sql` |
| T3 old-table fix (prepared, not run; dry run OK) | `sql/ad_hoc/q-fix_core_pancake_warehouse_policy.sql` |
| T3 D2/D3 test | `tests/test_warehouse_policy_prefix.py` |
| T4 live-only routines (each equal to live after CRLF → LF) | `sql/functions/reportdb.fn_order_{product_inventory_summary,product_revenue_summary,revenue_summary,sku_master,sku_warehouse_master,target_master}.sql`, `reportdb.fn_performance_snapshot.sql`, `reportdb.fn_sale_online_thai.sql`, `reportdb.fn_stats_product.sql`; `sql/procedures/reportdb.sp_{sales_performance,stock_inventory}_dashboard_daily.sql`, `sysdb.sp_data_insert_log_V{2,3}.sql` |
| T4 archived (not live anywhere: 11 dropped after the 10-28 snapshot, 1 never deployed) | `sql/archive/zarchived-{core_pancake.sp_core_product_inventory_insert, core_pancake.sp_core_variations_inventory_insert, core_pancake.sp_core_warehouse_transfers_insert, dianplus.sp_dianplus_core_inventory_insert, jushuitan.sp_jushuitan_core_order_insert, jushuitan.sp_jushuitan_core_order_item_insert, magento.sp_magento_core_order_insert, magento.sp_magento_core_order_item_insert, raw_pancake.sp_check_partition_insert_dates, surfosm.sp_surfosm_core_order_insert, surfosm.sp_surfosm_core_order_item_insert, surfosm.sp_surfosm_core_order_return_insert}.sql`; link in `sql/checks/README.md` |
| T5 repointed readers (table names only) | `reportdb.fn_dim_sku`, `fn_product_inventory_overseas_shipment`, `fn_product_inventory_summary_v2`, `fn_assortment_seg_cont_by_warehouse`, `fn_order_product_inventory_summary`, `sp_stock_inventory_dashboard_daily` |
| T6 tests | `tests/test_warehouse_sales_names.py` (reviewed table repoint in the full-body comparison), `tests/test_warehouse_inventory_names.py` (fixture table name) |

The 34 functions and 1 check script repointed in @thread:thr_9b2q2q7sia are part of the same deploy.

### lsoul_dbt
| Change | Files |
|---|---|
| T1 `images` | `models/stage/pancake/stg_pancake__variations.sql`, `models/core/pancake/core_pancake__variations.sql`, `models/core/pancake/_core_pancake.yml`, `docs/sources/pancake.md` |
| T2 history | `models/raw/pancake/src_pancake.yml`, `models/stage/pancake/stg_pancake__orders_returned_history.sql`, `models/core/pancake/core_pancake__orders_returned.sql`, `tests/pancake_orders_returned_history_cutover.sql`, `scripts/test_pancake_orders_returned.py`, `docs/model-inventory.md` |

## Verified (read-only / offline)
- T1: compiled `core_pancake__variations` dry-runs; `images` equals live for all 4,467 variations.
- T2: compiled model with history (taken from the live table) = 728 + 934 = 1,662 rows, the live count;
  pre-cutover rows hash-equal live; no date comes from both parts.
- T3: new core table matches the policy; old table has the 7 known mismatches; UPDATE dry-runs.
- T4: 85 live routines vs repo: 0 live-only, 0 repo-only, 0 duplicates.
- T5: old → new tables keep every column and type (except `variations.images`, added by T1); dry runs pass
  for the small readers. The large readers were not dry-run (too large to paste); column parity covers the
  table-name change.
- Offline: `validate_repo.py` exit 0; `sql_index.py --check` clean; unittest 44 failures, all pre-existing
  (0 new against the 47-failure pre-repoint run). dbt: parse, `check_project.py` 0 errors, script tests,
  sqlfluff on changed files. `render_models.py` reports `images` as extra only because the `sql/live`
  snapshot predates the column (refresh needs `gcloud`/`bq`).

## Deploy order (each step needs the owner's go-ahead)
1. Re-baseline the old objects on the deploy day (same Vietnam date as the comparison) if the
   2026-11-05 baseline is stale.
2. Run `sql/ad_hoc/q-freeze_pancake_orders_returned_history.sql` (after the `raw` dataset exists; see decision 3).
3. dbt (prod): `dbt build -s stg_pancake__variations stg_pancake__orders_returned_history core_pancake__variations core_pancake__orders_returned --full-refresh`.
   `--full-refresh` is required: `images` sits mid-table (`on_schema_change=fail`), and history is unioned
   only on full builds. Check that `core.core_pancake__variations.images` is filled and that orders_returned starts 2025-06-11.
   Also refresh the sale-end seed and `--full-refresh` `core_pancake__product` (decision 5).
4. Deploy `core_pancake.sp_pancake_core_warehouse_insert` (policy-aware), then run `q-fix_core_pancake_warehouse_policy.sql`.
5. Deploy reportdb functions dependencies first: `fn_dim_sku`, `fn_product_variations_warehouse_summary`,
   `fn_china_product_inventory`, `fn_thailand_product_inventory`, `fn_order_product_revenue_summary`, then the
   `fn_sale_*` family, `fn_product_inventory_summary(_v2)`, `fn_stats_product(_v2)`, `fn_product_inventory_overseas_shipment`,
   `fn_assortment_seg_cont_by_warehouse`, `fn_order_product_inventory_summary` (decision 2), then `sp_stock_inventory_dashboard_daily`.
   One file at a time with `bq query … < file`; each prints `Replaced …`.
6. T7 comparison against the baseline; attribute every difference to D1–D3, product/variation_warehouses data or non-determinism.
7. Refresh `sql/live/` (docs/warehouse-definition-sync.md).

## Rollback
- Routines: redeploy the previous definition from `sql/live/bigquery/<dataset>/routines/<name>.sql`
  (or `git show HEAD:<file>`), `CREATE` → `CREATE OR REPLACE`.
- dbt: revert the model changes and `--full-refresh` the two core models.
- Old warehouse table: the 7 previous values (country VIETNAM for CN/TH Backup, TH EmSphere, TH Office;
  type P for 480F, Defective, Marketing) are listed in the fix script's header; restore by UPDATE.
- Frozen history table: nothing else reads it; drop it after reverting the dbt source.

## Report only (no change)
- Views without an editable file (2026-10-28 snapshot): 225, of which 218 are Google Ads transfer views;
  the rest are `dataform.order_revenue_summary`, `dev_staging.stg_pancake__order`,
  `jushuitan.stg_jushuitan_taobao_tmall_order_manual`, `reportdb.dash_highlights`, `reportdb.dash_store_hour_wow`,
  `reportdb.v_ai_report_prompts`, `stg_pancake.stg_order`.
- Scheduled queries (snapshot): `sp_sales_performance_dashboard_daily` and `sp_stock_inventory_dashboard_daily`
  (02:00 daily; procedures now have files); `daily_check_partition_insert_dates_V2` (disabled; calls
  `reportdb.sp_report_raw_pancake_data_import_status`, which is not live).
- Writers left on `core_pancake` (out of scope): the 9 `core_pancake.sp_*_insert` procedures and `sql/core/core_pancake.*`.

---

# Phase 2 update (2026-11-06, @thread:thr_fzwqdp2wyw)

Evidence: [T7 and findings report](core-pancake-repoint-t7-report.md),
[schedule, lineage and per-table checklist](core-pancake-schedule-map.md), and the runbook
[docs/core-pancake-load-monitoring.md](../docs/core-pancake-load-monitoring.md). **Still nothing deployed or committed.**

## Readiness verdict

| Part | State |
|---|---|
| Local implementation | **Complete** for the repoint and the Phase 2 items. One decision remains open (below) |
| Offline validation | **Passed.** `validate_repo.py` 0; `sql_index.py --check` 0 problems; unittest 165 tests: 29 failures + 15 errors, identical to the HEAD baseline (44 = 44, **0 new**); dbt `parse` 0, `check_project.py` 0 errors, script tests 153 OK. `render_models.py` has 2 known errors (`images` is extra against the stale `sql/live` snapshot) |
| Read-only warehouse validation | **Passed with limits.** 147 old-vs-new calls: 112 equal, 7 within float tolerance, 19 different (all attributed), 8 blocked by BigQuery's planning limit (`fn_product_inventory_summary` / `_v2`, both sides), 1 old-side failure (T11). Candidates verified against the old tables; large routines dry-run per statement |
| Production deployment | **Still required**, and blocked by prerequisites (below). Tomorrow's 08:00 job runs lsoul_dbt `4f7c664` and does **not** exercise any of this |

## Phase 2 changes

### lsoul-data-warehouse
| File | Change |
|---|---|
| `sql/functions/reportdb.fn_order_product_inventory_summary.sql` | `fn_china_product_inventory(1,'')` → `(1,1)` with the evidence in a comment (T11) |
| `tests/test_table_function_call_args.py` | New: literal arguments of every reportdb TVF call must match the callee signature (caught the T11 bug) |
| `sql/checks/check_pancake_sale_end_list_drift.sql`, `sql/checks/README.md` | New read-only drift check: dbt sale-end seed vs the latest live Dataform UPDATE (`in_sync` today) |
| `scripts/pancake_candidate_sql.py` | New: offline candidate SELECTs for unbuilt dbt models (rendered with lsoul_dbt's renderer; raw mapped to live datasets) |
| `scripts/compare_pancake_repoint.py` | New: old-vs-new metrics for the 147 calls (read-only, aggregates) |
| `scripts/monitor_core_pancake_load.py`, `docs/core-pancake-load-monitoring.md` | New: read-only baseline/post-run monitor (5 layers) and runbook |
| `tests/test_core_pancake_monitoring.py` | New: read-only SQL guard, verdict rules (mutation-checked), dbt log parsing, comparison rewrite |
| `tasks/core-pancake-repoint-{plan,todo,review}.md`, `tasks/core-pancake-repoint-t7-report.md`, `tasks/core-pancake-schedule-map.md` | Plan, results, evidence |

### lsoul_dbt
No changes in Phase 2. The sale-end seed is current, so no refresh was needed.

## Decisions for the owner (updated)

1. **Phase 1's decision 1 (T7 needs `bq`):** resolved. T7 ran read-only.
2. **Sale-end residue (replaces Phase 1's decision 5; the seed is *not* stale).** 54 products are flagged
   SYS_01_SALE_END only in the old table. They were in the daily sale-end list from 2026-06-18 to 2026-07-15, then
   removed, and the old procedure never clears the tag. After the cutover, reports treat them as active (`fn_dim_sku`
   `is_sale_end` 3,514 → 3,460). Confirm the 2026-07-15 removal was intended. If those products should stay sale-end,
   add them back to the Dataform list and the seed.
3. **`fn_order_product_inventory_summary` (Phase 1's decision 2):** resolved by evidence. `(1,1)` keeps the original
   meaning (per-Kho, 1 year). The alternative `i_type 0` (aggregated) would be a behaviour change. No caller since 2026-06-10.
4. **Deploy prerequisites (ordering):**
   - Dataset `raw` doesn't exist. The freeze script, the dbt history source, and the repo's
     `sp_stock_inventory_dashboard_daily` (2 `raw.` lines) all need it. Deploy the raw-dataset migration first, or
     ship this batch with `raw_pancake` names.
   - Commit both repos, then `deploy/cloudrun.sh apply` (lsoul_dbt) so the scheduled job runs the new models.
   - Full-refresh `core_pancake__variations` and `core_pancake__orders_returned` after the freeze (Phase 1 deploy step 3).
5. **Docs out of date (no change made):**
   - lsoul_dbt `deploy/README.md` says the trigger is paused at 09:00; live it is ENABLED at 08:00.
   - `src_pancake.yml` and the docs say `raw_orders_returned` has no scheduled loader; live it is loaded daily at 07:00
     by service `pancake-orders-returned`, whose source isn't in this repo.

## AgentMemory and Graphify

- **AgentMemory** (MCP `mcp__agentmemory__*`; there is no AgentMemory skill file). `memory_smart_search` found no
  record of this task, only unrelated lsoul_dbt tool notes; expanding them returned nothing. One project-scoped handoff
  was saved at the end of this stage (decisions, evidence paths, blockers; no rows or secrets).
- **Graphify** (`~/.claude/skills/graphify`). Queried the existing `lsoul_dbt/graphify-out` graph (built 2026-11-05 17:45,
  stale for files edited since). Its dbt model nodes have degree 0, with no `ref()`/`source()` edges, so it can't trace
  model lineage. Lineage was taken from the dbt manifest and a grep of `sql/` instead. No graph was built or updated,
  and nothing was sent to an external service.

## Review stage (2026-11-06)

Fixed:
- **T7 report:** the fn_sale_* row now says 118 calls (105 equal, 3 within tolerance, 10 different), not 66. The claim
  that every order/customer reader was equal is replaced: all differences trace to product, warehouse or D8.
- **Monitor:** a failed execution, or a dbt summary with ERROR/SKIP > 0, now makes the verdict FAIL (it was UNKNOWN).
  The last `Done.` summary is used. The scheduled execution (07:55–09:30 ICT) is preferred over an earlier manual run.
  `--as-of` must parse as a timestamp before it goes into SQL. New tests fail on the pre-review code and pass after.
  Re-validated on the 2026-11-06 run: PASS.
- **Comparison:** NaN sums on both sides no longer count as a difference.
- **Runbook:** the monitoring JSON is ignored by the `*.json` rule (`data/` itself isn't ignored).

FYI, not changed:
- `compare_pancake_repoint.bind()` replaces parameter names textually. A string literal holding a parameter name
  would be rewritten too. None does today: 112 calls reproduce the old result exactly.
- The `stats_inventory_variations` reconciliation compares a column subset of the model's DISTINCT (a heuristic,
  documented in the runbook).
- `git diff --check` flags trailing whitespace on earlier table-name-only edits. Those lines keep live's original
  whitespace, so they're left as is.
- Raw-dataset workstream: `sql/staging/stg_meta.stg_ads_reporting_my.sql` reads `raw.stg_ads_reporting_my`; HEAD
  had `raw_meta.stg_ads_reporting_my`. The raw table is `raw_ads_reporting_my`, so this looks like an existing name bug.
