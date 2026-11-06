# Plan: finish the core_pancake → core repoint

Continues @thread:thr_9b2q2q7sia (34 functions plus 1 check script repointed in the repo and not deployed;
baseline of 142 calls recorded 2026-11-05). Tasks: [core-pancake-repoint-todo.md](core-pancake-repoint-todo.md).
The earlier warehouse-identity plan ([plan.md](plan.md), [todo.md](todo.md)) is left untouched.

## Spec

### Objective
Every reader of `core_pancake.core_*` in `reportdb` reads `core.core_pancake__*` instead. The new tables
are complete and correct, and the repo holds one editable file for every live routine. Old-vs-new results
are compared and explained. **Nothing is applied to production until the user reviews the whole batch.**

### Decisions (user, 2026-11-05)
| # | Topic | Decision |
|---|---|---|
| D1 | orders_returned history | Freeze the old `core_pancake.core_orders_returned` rows dated before the first raw window (2025-06-11 … 2026-02-10, 728 rows) into dbt and union them into `core_pancake__orders_returned`. No API backfill. |
| D2 | Country rule | The leading prefix decides: `CN –` → CHINA, `TH –` → THAILAND, `VN –` → VIETNAM. Unprefixed names keep their current country. |
| D3 | Warehouse type | Keep all policy values: 480F Central Warehouse = B, TH Office Stock = M, VN Marketing Stock = M, VN Defective Stock = NONE. |
| D4 | Deploy gate | No production change before review: no CREATE OR REPLACE, table DML, or dbt run against prod datasets. Validate with dry runs, read-only GoogleSQL checks, and scratch/temp copies only. |
| D5 | Live/repo sync | Routines, both directions: an editable file for every live-only routine (repoint the ones that read `core_pancake`). Repo routine files missing from asia-southeast1: check other locations; archive (`zarchived-`) any that aren't live anywhere. Views and scheduled queries: report only. |
| D6 | Old warehouse table | Prepare a corrective UPDATE for `core_pancake.core_warehouse` and change `sp_pancake_core_warehouse_insert` to apply the same policy (held for review). |
| D7 | `fn_dim_sku` | Repoint every table, including `core_variations` → `core.core_pancake__variations` (needs `images`, T1). |
| D8 | Undeployed repo changes | `fn_product_inventory_overseas_shipment`, `fn_product_inventory_summary_v2` and `fn_assortment_seg_cont_by_warehouse` ship with their pending repo changes plus the repoint. Deploy is held per D4. |

### Facts established in Plan (read-only)
- `core.core_pancake__warehouse` already matches D2/D3 for every prefixed warehouse; the old table has 7
  mismatches (CN/TH backups and TH EmSphere/Office = VIETNAM, 480F = P, Defective/Marketing = P).
- Raw `raw_pancake.raw_orders_returned` partitions span 2026-03-12 … 2026-11-05 (238). The new table has 934 rows
  from 2026-02-11, the old table has 1,662 rows from 2025-06-11.
- `images` is STRING in `raw_pancake.raw_product_variations` and `core_pancake.core_variations`. The dbt
  `stg_pancake__variations` / `core_pancake__variations` models don't select it. `fn_dim_sku` uses
  `ANY_VALUE(NULLIF(TRIM(images),''))`.
- No live routine reads `core.core_pancake__*` yet. 50 live routines read `core_pancake.core_*` (39 reportdb
  functions/procedures plus 9 core_pancake writers, which are out of scope).
- Live-only routines (asia-southeast1, no matching file name): `core_pancake.sp_pancake_core_variations_insert`,
  `reportdb.fn_fmt_money`, `fn_fmt_money_pair`, `fn_money_scale`, `fn_money_unit`,
  `fn_order_product_inventory_summary`, `fn_order_product_revenue_summary`, `fn_order_revenue_summary`,
  `fn_order_sku_master`, `fn_order_sku_warehouse_master`, `fn_order_target_master`, `fn_performance_snapshot`,
  `fn_sale_online_thai`, `fn_stats_product`, `sp_sales_performance_dashboard_daily`,
  `sp_stock_inventory_dashboard_daily`, `sysdb.sp_data_insert_log_V2`, `sp_data_insert_log_V3`.
  Some may already be covered by files with different names (e.g. `reportdb.fn_money_helpers`); resolve by CREATE name.
- dbt project: `/Users/tony.pham/Downloads/lsoul_dbt` (branch `main`, has unrelated local edits in
  `logs/dbt.log`, `stg_surfosm__inventory.sql`; leave them alone).

### Boundaries
- Always: edit `sql/<layer>/<dataset>.<object>.sql`, never `sql/live/`. Keep each repoint table-name-only
  except where D3/D8 say otherwise. Run `python3 scripts/validate_repo.py`, `python3 -m unittest discover -s tests`,
  `python3 scripts/sql_index.py --check`, dbt `parse`/`compile`.
- Ask first: any write to BigQuery prod datasets, dbt `run`/`build` against prod, API ingestion.
- Never: read `.env`/`credentials/`, print customer rows, push, or rewrite history.

### Success criteria
1. `core_pancake__variations` (dbt model, YAML docs/tests and staging) exposes `images` (STRING) with the live
   procedure's semantics. The dbt compiled SQL dry-runs in BigQuery.
2. `core_pancake__orders_returned` compiled SQL yields ≥ the old table's date coverage (min date 2025-06-11), and
   rows before the first raw window equal the old table (hash-compared through a read-only query).
3. Repo policy (`sql/config/warehouse_policy.json`), dbt macro and a prepared UPDATE for the old table all satisfy
   D2/D3. A test asserts prefix ↔ country for every prefixed warehouse.
4. Every live routine has exactly one editable file (resolved by CREATE name). No live-only routine remains.
   Repo-only routine files are either confirmed live elsewhere or archived.
5. `fn_dim_sku`, the 3 D8 functions and the live-only readers read only `core.core_pancake__*` (no
   `core_pancake.core_` references in any reportdb object except writers). Each compiles in a dry run.
6. Comparison report: the new SQL bodies (run as ad-hoc queries over the new tables, not deployed) vs the
   2026-11-05 baseline, for all 142 calls plus the new objects. Every difference is attributed to D1–D3,
   `product`/`variation_warehouses` data differences or known non-determinism.
7. A review packet lists every file, the exact deploy order and the rollback, then stops for the user's review.

## Sequence
`T1 images (dbt) → T2 orders_returned history (dbt) → T3 warehouse policy (repo+dbt+old table) → T4 live/repo
sync → T5 fn_dim_sku + D8 functions + live-only readers → T6 tests/validation → T7 comparison → T8 review packet`

T1–T3 are independent data fixes. T4 must precede T5 (the new files are T5's inputs). T7 needs T1–T5.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Adding `images` to an incremental merge model doesn't populate old rows | High | `on_schema_change='append_new_columns'` plus a documented `--full-refresh` (or targeted backfill) in the deploy steps; check the null rate in the comparison |
| Frozen history double-counts dates the raw window also covers | Med | Cut over strictly at the first raw window start; test that no inserted_at date appears in both parts |
| Baseline is date-relative (current_date) | Med | Compare on the same Vietnam day, or re-baseline old SQL alongside new in one run |
| `fn_product_inventory_summary` non-deterministic | Med | Compare with tolerance plus key-set equality; report as such |
| `fn_product_inventory_summary_v2` too complex to baseline | Med | Compare per-mode subsets or row counts plus key hashes |
| Repo-only routines live in another region (US) | Low | Query each location's INFORMATION_SCHEMA before archiving |

## Open questions
None blocking. Deploy order and dbt full-refresh timing are confirmed in the T8 review.

## Plan refresh (2026-11-05, @thread:thr_34rtwqfn2y)
The user approved this plan in @thread:thr_8sfmn3kgdn ("Approve"). It continues here unchanged; no task has started.
- Live (read-only): 0 routines read `core.core_pancake__*`; 48 read `core_pancake.core_*` (39 reportdb + 9 writers;
  the "50" above was a miscount). Newest routine `last_altered` is 2026-11-05 09:43 UTC, before this plan, so the
  baseline still holds.
- lsoul_dbt: `stg_surfosm__inventory.sql` is now committed (`2dc293d`); only `logs/dbt.log` is dirty. Leave it alone.
- Workspace: the build depends on uncommitted repoint edits on `main` here, so it stays in this checkout and on this
  branch. No worktree or new branch (user preference: keep the current branch). Agent Flow's Review stage stands in for
  build-and-review's reviewer thread.
- Disk is 4.7% free (22 GiB). The Orbyn cleanup report found nothing to free. Keep dbt `target/` output small.

## Phase 2 plan (2026-11-06, @thread:thr_fzwqdp2wyw)

Source: the optimised prompt in @thread:thr_k5hs4j9ska. Finish the local implementation and verification, then
hand over read-only monitoring for **tomorrow, Sat 2026-11-07 (Asia/Ho_Chi_Minh)**. Today in Vietnam is
Fri 2026-11-06, 15:58 at plan time. **Deploy nothing.** Tasks: T7 (reopened) and T9–T17 in
[core-pancake-repoint-todo.md](core-pancake-repoint-todo.md).

### Boundaries for Phase 2 (stricter than D4)
- **Allowed:** local edits in both repos; offline checks; bounded read-only `gcloud` metadata/log reads;
  read-only `SELECT`s and dry runs with `maximum_bytes_billed` set; AgentMemory recall and one project-scoped handoff save.
- **Not allowed:** remote DDL/DML; dbt `run`/`build`/`seed`/`snapshot`/`test`/`source freshness`; full refresh; creating the
  history table; warehouse UPDATE; routine replacement; scheduler/job changes; triggering ingestion or the job; commit, push,
  branch, stash, PR. Keep the current branch (`main`) in both repos and leave unrelated edits alone (raw-dataset work).
- **dbt compile is not offline.** `dbt_project.yml` has an `on-run-start` hook (`macros/incremental/watermark.sql`) that
  creates the `dbt_meta` watermark table, and dbt runs `on-run-start` for `compile` too. Use the offline
  `scripts/render_models.py` renderer for candidate SQL. Run `dbt compile` only with the hook confirmed off for that
  invocation, never against `prod`.
- No customer-level rows in terminal output, artifacts, memory or Git: aggregates, counts and hashes only.

### Facts found while planning (to recheck in T9)
- **Scheduler (per repo docs, unverified live):** Cloud Run Job `dbt-daily-build` runs `dbt source freshness` then
  `dbt build --selector daily` with target `prod`. Cloud Scheduler `dbt-daily-build-trigger` fires `0 9 * * *` Asia/Ho_Chi_Minh
  and was **created paused** (`lsoul_dbt/deploy/README.md`). If it is still paused, there is no dbt run tomorrow, and monitoring
  must say so rather than PASS. The image tag is the git SHA and the first log line prints `GIT_COMMIT`.
- Selector `daily` = `models/` + `seeds/`, excluding tag `unscheduled`. No Pancake model is tagged `unscheduled` (only the
  Jushuitan manual and mart AI models are), so all 10 `core_pancake__*` models are in scope if the deployed revision has them.
- The deployed image runs **committed** code. Both repos have large uncommitted diffs (this work plus the raw-dataset
  migration), so tomorrow's run validates deployed-table freshness only, **not** the local fixes.
- Uncommitted dbt sources point Pancake at dataset `raw` (raw-dataset work, not live yet). Candidate SQL for T7 must render
  against the datasets that exist live today (`raw_pancake`), or the comparison is invalid.
- Graphify: `lsoul_dbt/graphify-out/graph.json` was built 2026-11-05 17:45 (HEAD 1b62441 committed 17:46). The dirty files are newer, so the graph is
  stale for them. `lsoul-data-warehouse` has no graph. AgentMemory: no skill file; the `mcp__agentmemory__*` MCP tools are
  available (recall/smart_search/save).
- Guidance read: both repos' AGENTS.md/CLAUDE.md, Orbyn library AGENTS.md (harness resolved for both roots: work mode
  not set, so per the user's instruction we work in place; max 2 children), Holistics blueprint AGENTS.md/instruction.md/SKILL.md.
  Untools gate: **Inversion** (rollout and monitoring readiness), with **Issue Trees** for T7 difference attribution. Source: local card in
  `references/untools-blueprint.md` (**local fallback**: no live fetch in this stage).

### Inversion: how this could go wrong → prevention → validation
| Failure | Prevention | Validation |
|---|---|---|
| T7 "passes" by querying already-built new tables that lack the unbuilt fixes | Candidate CTEs from rendered model SQL for variations/orders_returned/product | Report states, per call, which inputs were candidate vs live |
| Sale-end seed refreshed from a stale snapshot | Read the live Dataform operation/live table flags read-only; record source and time | Diff of the seed against the live flags = 0 for active products |
| Monitoring reports PASS while the trigger is paused or the run was a no-op | Five independent layers (scheduler → revision → dbt results → BQ jobs → source→target) | UNKNOWN unless every layer has evidence |
| A raw-dataset edit overwrites live's 2026-11-04 `sp_stock_inventory_dashboard_daily` change | Diff the repo file against live DDL (INFORMATION_SCHEMA read) | Only the intended `raw.` repoints differ |
| A "fix" to `fn_china_product_inventory(1, '')` changes business meaning | Establish semantics from signature, callers and history first | Either a tested fix with its rationale or a named open decision |
| A test is weakened to go green | Baseline the HEAD test run in a temp export (`git archive`), not by editing tests | Per-test diff: pre-existing vs new failures |

### Sequence
`T9 recheck + scope → (T10 sale-end, T11 fn_china call, T12 raw-dataset reconcile) → T13 large routines → T7 compare →
T14 schedule map → T15 monitoring package → T16 offline checks → T17 packet, memory, handoff`.
T10–T12 are independent. T13 and T7 need T10–T12. T14 is independent of T7 and can run in parallel. T15 needs T14.

### Phase 2 success criteria
1. Every recheck item (1–7 of the prompt) is classified as confirmed, changed or resolved, with evidence paths.
2. Local seed, function fix (or recorded decision) and reconciled procedures, each with a test or check.
3. Offline checks run with a HEAD baseline; 0 new failures, or each one explained.
4. T7 report under `tasks/`: per-call status (equal / explained diff / blocked with the exact unexecuted query).
5. Schedule map with live evidence (or explicit UNKNOWN) and a per-table checklist for all 10 models.
6. Read-only monitoring SQL plus a runbook with baseline/post-run commands and a justified check time for 2026-11-07.
7. Readiness verdict split into: local implementation, offline validation, read-only warehouse validation, deployment still required.

### Open decisions (isolated, not blocking the build)
- `fn_order_product_inventory_summary` → `fn_china_product_inventory(1, '')`: intended second argument (T11).
- Deploy-time items carried over from the review packet: freeze-table dataset (`raw` vs `raw_pancake`), full-refresh timing, sale-end seed deploy.
