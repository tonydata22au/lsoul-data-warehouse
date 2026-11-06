# Tasks: finish the core_pancake → core repoint

Plan and spec: [core-pancake-repoint-plan.md](core-pancake-repoint-plan.md). D1–D8 are the user's decisions.
No task writes to production (D4).

## T1: `images` on core_pancake__variations (dbt)
- [x] Port the live `sp_pancake_core_variations_insert` handling of `images` into `stg_pancake__variations`
      and `core_pancake__variations`. Add the column to `_core_pancake.yml` and set `on_schema_change` so a
      merge adds it. *Done 2026-11-05: `json_value(images, '$[0]')` (live staging rule, 4,563/4,563 rows).
      Kept `on_schema_change=fail`: the column sits mid-table like live, so deploy needs `--full-refresh`.*
- [x] Add an editable repo file for `core_pancake.sp_pancake_core_variations_insert` (live-only, D5). *SHA-equal to live.*

Acceptance: compiled model selects `images` STRING with the same trim/null semantics as live.
Verify: `dbt parse` and `dbt compile -s core_pancake__variations`; BigQuery dry run of the compiled SQL;
read-only query showing the old and compiled-new `images` per variation_id are equal.
Files: lsoul_dbt `models/stage/pancake/stg_pancake__variations.sql`, `models/core/pancake/core_pancake__variations.sql`,
`models/core/pancake/_core_pancake.yml`. Size: S.

## T2: full history for core_pancake__orders_returned (dbt, D1)
- [x] Freeze the old rows dated before the first raw window start as a dbt-owned history source (seed, or a
      one-time snapshot table, created only after review). Union them into the model with a strict cutover date.
      *Done: one-time table `raw.raw_orders_returned_history` (dataset renamed by the raw-dataset work; originally `raw_pancake`) (prepared
      `sql/ad_hoc/q-freeze_pancake_orders_returned_history.sql`, not run; not a seed because rows hold customer
      names), source + `stg_pancake__orders_returned_history`, unioned on first build/full refresh, cutover 2026-02-11.*

Acceptance: compiled output covers 2025-06-11 onward. Pre-cutover rows hash-equal the old table, and no
inserted_at date is sourced from both parts.
Verify: `dbt compile`; read-only coverage and hash queries against the compiled SQL; a dbt test for the cutover.
Files: lsoul_dbt model, yml and seed/source definition. Size: S.

## T3: warehouse country/type policy (D2, D3, D6)
- [x] Confirm `sql/config/warehouse_policy.json` and the dbt `lsoul_warehouse_policy` macro match D2/D3 (they
      appear to already). Fix any drift.
- [x] Add a test: every `XX –` prefixed warehouse maps to its country, and 480F = B. *`tests/test_warehouse_policy_prefix.py`.*
- [x] Change `sp_pancake_core_warehouse_insert` to apply the policy. Prepare `sql/ad_hoc/` UPDATE for
      `core_pancake.core_warehouse` (not run). *Procedure already policy-aware in the repo (2026-11-02 work);
      `sql/ad_hoc/q-fix_core_pancake_warehouse_policy.sql` fixes the 7 rows, dry-run OK.*

Acceptance: the repo, dbt and the prepared old-table fix agree. The new core table already matches (re-check).
Verify: unittest; read-only query of both tables vs the policy. Files: ≤5. Size: M.

## Checkpoint A (after T1–T3)
- [x] `python3 scripts/validate_repo.py`, unittest, dbt parse pass. *dbt side green. validate_repo fails only on
      another session's `tasks/raw-dataset-todo.md` link; unittest failures are the T6 set.*

## T4: live/repo routine sync (D5)
- [x] Resolve each of the 18 live-only routines by CREATE name. Create `sql/<layer>/<dataset>.<object>.sql`
      from the live DDL for the missing ones.
- [x] Check the 13 repo-only routine files against every BigQuery location. Archive any that aren't live anywhere.
      *13 live-only files created (hash-equal live); 12 repo-only files archived (US has no routines).*
- [x] Report views and scheduled queries without editable files (report only). *In [the review packet](core-pancake-repoint-review.md).*

Acceptance: no live routine lacks a file; `sql_index.py --check` passes. Verify: script comparison against
`INFORMATION_SCHEMA.ROUTINES` (all locations). Size: M–L; split per dataset if more than 5 files.

## T5: repoint the remaining readers (D7, D8)
- [x] `fn_dim_sku`: all tables including `core_variations`.
- [x] `fn_product_inventory_overseas_shipment`, `fn_product_inventory_summary_v2`,
      `fn_assortment_seg_cont_by_warehouse`: pending changes plus repoint.
- [x] Live-only readers from T4 (`fn_order_product_inventory_summary`, `sp_stock_inventory_dashboard_daily`, and
      any other that reads `core_pancake.core_*`).

Acceptance: no reportdb object (except writers) references `core_pancake.core_`. Every body dry-runs.
Verify: grep plus BigQuery dry run per object. Size: M.

## T6: tests and offline validation
- [x] Update snapshot/allow-list tests for the table mapping. Fix the 15 failures attributed to the repoint.
      Don't mask the 47 failures that predate this work; list them.

Verify: `python3 scripts/validate_repo.py`; `python3 -m unittest discover -s tests`; `python3 scripts/sql_index.py --check`.

## Checkpoint B (after T4–T6)
- [x] All offline checks green, apart from the listed pre-existing failures. *44 pre-existing, 0 new.*

## T7: compare again (reopened in Phase 2; read-only SELECTs and dry runs are authorized)
- [x] *Done 2026-11-06 (Phase 2): [T7 report](core-pancake-repoint-t7-report.md). 147 calls: 112 equal, 7 within float tolerance, 19 different (all attributed), 8 blocked by the BigQuery planning limit on both sides, 1 old-only failure (T11).* Run each new body as an ad-hoc read-only query (with T1–T3 applied through compiled CTEs or temp
      tables) for the 142 baseline calls plus the new objects. Compare row counts, hashes and per-column sums.
- [x] Attribute every difference (D1, D2/D3, product/variation_warehouses data, non-determinism).

Verify: comparison report saved under `tasks/`. No aggregated personal data in the report.

## T8: review packet, then stop
- [x] List the files, deploy order (dbt changes → old-table fix → functions), rollback (redeploy the live DDL
      snapshot) and the full-refresh steps. Wait for the user's review. Deploy nothing.
      *[core-pancake-repoint-review.md](core-pancake-repoint-review.md).*

---

# Phase 2 (2026-11-06): finish, verify, monitor tomorrow (2026-11-07)

Plan: [Phase 2 plan](core-pancake-repoint-plan.md#phase-2-plan-2026-11-06-threadthr_fzwqdp2wyw). Read-only cloud access only.
No dbt run/build/seed, no DDL/DML, no deploy.

## T9: recheck state and scope
- [x] Diff both repos and tag each changed file: Pancake repoint / raw-dataset / other. Touch only the first. *Phase 2 touched only new files plus `fn_order_product_inventory_summary.sql` and `sql/checks/README.md`; no dbt file.*
- [x] AgentMemory recall (`mcp__agentmemory__memory_smart_search`), plus a Graphify query on `lsoul_dbt/graphify-out` (freshness noted). *Memory had no task-specific record. The graph has dbt models with degree 0 (no ref edges), so lineage came from the manifest.*
      Build a lineage table: ingestion → raw → stage → core → reportdb readers → scheduled consumers. Check every edge against SQL, refs or config.
- [x] Recheck items 1–7 from the prompt against current files and read-only live metadata.
Acceptance: a scope table and a lineage artifact, each claim with a path or query. *Lineage in [core-pancake-schedule-map.md](core-pancake-schedule-map.md); items in the [T7 report](core-pancake-repoint-t7-report.md).*

## T10: sale-end seed (item 5)
- [x] Read the authoritative SYS_01_SALE_END list read-only (live Dataform operation and/or live `core_pancake.core_product` flags). *Live compilation = seed, 3,568 = 3,568. The 54 are old-table residue (in the list 2026-06-18…07-15 only).*
- [x] Refresh `lsoul_dbt/seeds/pancake/pancake_sale_end_display_ids.csv` locally if the evidence supports it. Do not run `dbt seed`. *Not supported: the seed is current. No change.*
- [x] Add drift detection (a `sql/checks/` read-only query and/or a dbt test) and document it. *`sql/checks/check_pancake_sale_end_list_drift.sql` → `in_sync`.*
Acceptance: the seed equals the live list as of the read time; the 54-product gap is closed for candidate SQL. Verify: count diff = 0 in a read-only query.

## T11: `fn_order_product_inventory_summary` → `fn_china_product_inventory(1, '')` (item 6)
- [x] Establish the meaning of the parameters (signature, body, other callers, git/live history). *JOBS history: written for (year_back, warehouse); `(1,'')` = 1 year, all, per Kho.*
- [x] If the meaning is established: a local fix plus a test and a dry run. Otherwise record the exact decision. *`(1,1)`; `tests/test_table_function_call_args.py` red→green; DDL dry-run OK.*
Acceptance: a fixed, dry-run-clean file with its rationale, or a named open decision. No guessed `(1, 1)`.

## T12: reconcile with the raw-dataset migration (item 7)
- [x] `sp_stock_inventory_dashboard_daily`: repo file = live DDL + intended `raw.` repoints only (diff against INFORMATION_SCHEMA). *5 lines differ: 3 core + 2 raw. Live 2026-11-04 change kept.*
- [x] Overlapping dbt sources/staging/procedures are consistent. The history source's dependency on dataset `raw` is verified (no creation). *Dataset `raw` doesn't exist. The freeze script, dbt history source and this procedure all need it first.*
Acceptance: a written diff summary; no lost live change.

## T13: validate the large routines (E)
- [x] `fn_dim_sku`, `fn_product_inventory_summary_v2`, `sp_stock_inventory_dashboard_daily`: dry-run from the file (definition),
      then the body's read statements over candidate inputs (body and branches). Never execute the procedure.
Acceptance: per routine, which level was validated and which branches weren't.

## Checkpoint C (after T9–T13)
- [x] validate_repo, unittest (against the HEAD baseline), sql_index --check, dbt parse plus offline scripts all green or explained.

## T7 (see above): comparison
- [x] Locate the 142 baseline calls and tooling (@thread:thr_9b2q2q7sia). Run old vs candidate on the same VN date with candidate CTEs.
- [x] Compare counts, multiplicities, key coverage, nulls, hashes and totals. Attribute differences (Issue Trees), including the historical 89,215/74,773, 5-order and 84-product findings.
Acceptance: `tasks/core-pancake-repoint-t7-report.md`, aggregates only; blocked calls list the exact unexecuted query.

## T14: verified schedule and dependency map
- [x] Read-only `gcloud`: the `dbt-daily-build-trigger` state/cron/tz/next run; the `dbt-daily-build` image, `GIT_COMMIT`, args, recent executions and duration;
      upstream Pancake loaders (Cloud Run services + triggers), including whether `raw_orders_returned` has an active loader.
- [x] Per model, whether the deployed revision's `daily` selector includes it; list excluded and manual-only models and sources with no loader.
Acceptance: `tasks/core-pancake-schedule-map.md` with an evidence ref per row, or UNKNOWN.

## T15: monitoring package for 2026-11-07
- [x] Read-only SQL with baseline and post-run modes, aggregates only, using verified columns. A per-table checklist for the 10 models. *`scripts/monitor_core_pancake_load.py` (SQL generated, read-only test); checklist in the schedule map.*
- [x] Five layers: scheduler launched → revision/target/selector → dbt results → BigQuery job writes → bounded source→target reconciliation
      (missing keys, mismatched values, duplicates, null keys, unexpected deletes). Results are PASS / "Run succeeded; no eligible source changes" / UNKNOWN / FAIL.
- [x] Runbook (`docs/` or `tasks/`): exact commands, check time = the verified schedule plus a justified buffer, where the logs are. *[docs/core-pancake-load-monitoring.md](../docs/core-pancake-load-monitoring.md). Validated on the 2026-11-06 run (PASS, 3 × NO_ELIGIBLE_CHANGES). Baseline for 11-07 taken.*
      State that the run does not validate undeployed fixes. A unittest asserts the SQL is read-only.
Acceptance: the package dry-runs; the runbook is executable as written.

## T16: offline checks (final)
- [x] `python3 scripts/validate_repo.py`; `python3 -m unittest discover -s tests` (vs HEAD baseline); `python3 scripts/sql_index.py --check`;
      dbt `parse`, `scripts/check_project.py`, `scripts/render_models.py`, script tests, sqlfluff on changed files; `--imports` only if isolated deps exist.

## T17: packet, memory, handoff
- [x] Update this todo and [core-pancake-repoint-review.md](core-pancake-repoint-review.md) with actual results and the readiness verdict (4 parts).
- [x] AgentMemory: save one project-scoped handoff (decisions, evidence paths, blockers, next steps; no secrets or rows).
- [x] Report AgentMemory/Graphify usage and their limitations.
