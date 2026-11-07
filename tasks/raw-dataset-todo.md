# Tasks: consolidate raw tables into dataset `raw`

Plan: [raw-dataset-plan.md](raw-dataset-plan.md) (cutover protocol, fingerprint definition).
Separate from `tasks/todo.md` (different, still-open work).

Shared sweep used in acceptance criteria. `OLD` matches qualified references; `OLD_PY` matches bare
dataset literals in Python, such as `DATASET_ID = 'dianplus'` and `os.getenv("BQ_DATASET", "surfosm")`, which
`OLD` alone misses in 11 writer files. On 2026-11-05, `OLD_PY` matched 30 cloud_run, 31 local_run and 32 schema
files, with no non-dataset hits. `sweep <paths>` must print nothing for the listed paths:

```text
OLD    = raw_pancake\.|raw_tiktok\.|raw_meta\.|(dianplus|jushuitan|magento|surfosm)\.raw_
OLD_PY = ["'](raw_pancake|raw_tiktok|raw_meta|dianplus|jushuitan|magento|surfosm)["']
sweep sql/... = rg -n -e "$OLD" <paths>
sweep src/... = rg -n -e "$OLD" -e "$OLD_PY" <paths>
```

The implemented guard, `tests/test_raw_dataset_refs.py`, adds a `(?<![\w-])` lookbehind to `OLD`. That way, file
names such as `bq-raw_pancake..raw_order.py` and `zarchived-raw_pancake.sp_….sql` (paths, not dataset
references) aren't flagged.
`EXCLUDE` = `sql/live/**`, `sql/archive/**` and the single file `sql/migrations/raw_dataset_consolidation.sql`. That file
must name the old datasets to copy from and reverse into, so it gets its own check in S8 part 2 instead. Every sweep
passes these as `--glob '!<path>'`. Nothing else under `sql/migrations/` is exempt.
Each code task is ≤ 5 logical units (one Cloud Run service folder is its `cr-*.py`; its
Dockerfile, requirements.txt and app_runner.py are unchanged).

## Phase 1: Python writers, one source at a time (offline; Build stage)

Pattern for every service: dataset default → `os.getenv("BQ_RAW_DATASET", "raw")`; table name,
write disposition and columns unchanged. Each task also updates the matching `local_run/` and
`schema/` variants, with the literal `raw`.

| Task | Scope | Depends on | Acceptance | Verify |
|---|---|---|---|---|
| P1 | Meta: `cloud-run-meta-ads-reporting-a`, `-ecom`; local `meta_ads_a/ecom/my.py`; schema `bq-raw_meta_ads_reporting_a.py` | none | `create_dataset_if_not_exists` creates `raw` in asia-southeast1; sweep clean on these paths | `py_compile` on changed files; `validate_repo.py`; `--imports` for the 2 services |
| P2 | TikTok VN: `tiktok-ads`, `tiktok-gmv-max-report`, `tiktok-reporting-basic-autction-ad`; local `tiktok_vn_*.py` (5); schema `bq-raw_tiktok_*.py` (5) | none | sweep clean | same, for the 3 services |
| P3 | TikTok TH: `tiktok-thai-ads`, `tiktok-thai-gmv-max-report`, `tiktok-thai-reporting-basic-autction-ad`; local `tiktok_thai_*.py` (5) | none | sweep clean; `tiktok-thai-ads` startup bug stays out of scope and is recorded | same (expect the known `tiktok-thai-ads` import failure to be unchanged) |
| P4 | Pancake orders: `pancake-order`, `pancake-order_returned`; local `pancake_order.py`, `pancake_orders_returned.py`; schema `raw_order`, `raw_orders_returned`; `tests/test_cloud_run_pancake_order.py` | none | `DATASET_ID` default `raw`; test asserts env override and default | `python3 -m unittest tests.test_cloud_run_pancake_order`; `--imports` |
| P5 | Pancake catalogue: `pancake-product`, `-product_variations`, `-variations`, `-ecom-product`; local `pancake_product_variations.py`; schema product, product_variations, variations, ecom_product | none | sweep clean | `py_compile`; `--imports` (4 services) |
| P6 | Pancake stats: `pancake-stats_order`, `-stats_product`, `-stats_inventory_product`, `-stats_inventory_variations`; local stats scripts (2); schema stats (4) | none | sweep clean | same |
| P7 | Pancake other: `pancake-customer`, `-inventory_histories`, `-warehouse_transfer`; local customer, inventory_histories; schema customer, inventory_histories, warehouse_transfer, purchase, transaction | none | sweep clean | same |
| P8 | Dianplus: 4 services + 4 local + 4 schema | none | sweep clean | same |
| P9 | Jushuitan + Magento: `jushuitan-order`, `magento-order` (`BQ_DATASET` default `raw`); local jushuitan (3), `magento_order.py`; schema (3) | none | sweep clean | same |
| P10 | Surfosm: 3 services + 3 local + 3 schema | none | sweep clean | same |

### Checkpoint A (after P1–P10)
- [ ] `sweep src/` is clean
- [ ] `python3 scripts/validate_repo.py`, `.venv/bin/python scripts/validate_repo.py --imports` and `python3 -m unittest discover -s tests` pass
- [ ] `python3 scripts/build_pipeline_manifest.py` regenerated; `--check` passes; `tests/test_pipeline_manifest.py` updated

## Phase 2: Repo SQL, one consumer group at a time (offline; Build stage)

Edit only the dataset qualifier. Don't touch `sql/live/` or `sql/archive/`. After each task, run
`python3 scripts/sql_index.py --check`.

| Task | Scope | Depends on | Acceptance |
|---|---|---|---|
| S1 | `sql/staging/stg_pancake.*` (5 files) | none | sweep clean on these files |
| S2 | `sql/staging/stg_tiktok.*`, `stg_meta.*` (5) | none | sweep clean |
| S3 | `sql/staging/dianplus.*`, `jushuitan.*`, `magento.*`, `surfosm.*` (11, in two commits: dianplus+magento, jushuitan+surfosm) | none | sweep clean |
| S4 | `sql/procedures/core_pancake.*` (6) | none | sweep clean |
| S5 | `sql/procedures/jushuitan.*` (2), `sql/functions/reportdb.fn_warehouse_operations.sql` | none | sweep clean |
| S6 | `sql/ad_hoc/` (2), `sql/monitoring/` (4), `sql/checks/README.md`, `sql/source_provenance.json` (partition checks read `raw.INFORMATION_SCHEMA`) | none | sweep clean |
| S7 | Migration script `sql/migrations/raw_dataset_consolidation.sql`, with sections freeze-check, copy, fingerprint, fence and reverse, matching the plan protocol. This is the **only** editable SQL that may name old raw datasets (it must, to copy from and reverse into them) | none | every statement is listed for all 31 tables; the set of `<old>.<t>` references it contains equals the 31-table inventory in the plan, each paired with `raw.<t>`; reviewed |
| S8 | Guard test `tests/test_raw_dataset_refs.py`, two parts. (1) **No-old-reference guard:** applies `OLD` + `OLD_PY` to `src/**/*.py` and `OLD` to `sql/`, excluding `EXCLUDE` (below); it must find nothing. (2) **Migration check:** the old references in `sql/migrations/raw_dataset_consolidation.sql` are exactly the 31 inventory tables, and each has a matching `raw.<t>`. Self-tests on synthetic in-memory files: a `DATASET_ID = 'dianplus'` line in a `src/` file is flagged; a `raw_pancake.raw_order` line in a `sql/staging/` or `sql/functions/` path is flagged; the same line in the migration path is **not** flagged by (1) | P1–P10, S1–S7 | written last, so it passes when added |
| S9 | Docs: `docs/pipelines.md`, `docs/troubleshooting.md`, `docs/running-pipelines.md`, `sql/README.md`, AGENTS.md | P1–P10 | sweep clean on docs; `validate_repo.py` link check passes |

### Checkpoint B (after S1–S9)
- [ ] `sweep src/ sql/ docs/ AGENTS.md` clean, excluding `EXCLUDE`
- [ ] The migration check in S8 passes: the migration names exactly the 31 old tables
- [ ] `python3 -m unittest discover -s tests` (including S8) and `validate_repo.py` pass

## Phase 3: lsoul_dbt (@project:proj_3598auxu2c; offline; Build stage)

Preserve that repo's unrelated uncommitted edits: stage only these lines.

| Task | Scope | Depends on | Acceptance | Verify |
|---|---|---|---|---|
| D1 | `models/raw/*/src_*.yml` `schema:` → `raw` (pancake, tiktok, meta, dianplus, jushuitan, magento, surfosm: 7 files) | none | each source resolves to `raw` | `dbt parse`; `dbt ls -s source:*` shows `raw` |
| D2 | `lsoul_raw_source` meta values in `models/core/{pancake,tiktok,meta}` | D1 | `rg "lsoul_raw_source': '(raw_pancake\|raw_tiktok\|raw_meta)\."` is empty | `dbt parse` |
| D3 | `lsoul_raw_source` in `models/core/{dianplus,jushuitan,magento,surfosm}` | D1 | same, for the `<source>.raw_` form | `dbt parse` |
| D4 | `deploy/README.md` ACL list, `docs/sources/*.md` | D1 | READER on `raw` documented for `dbt-runner@` | `dbt compile` |

### Checkpoint C: both repos are clean offline; human review before any live action

**Build status (2026-11-06, offline, uncommitted):**
- [x] P1–P10: 30 cloud_run services default to `os.getenv("BQ_RAW_DATASET", "raw")`; magento and surfosm-inventory keep
  `BQ_DATASET`, with default `raw`. local_run (31) and schema (32) use the literal `raw`. Pancake-order test updated:
  default `raw` plus an env override test (skipped here: no service deps in this machine's Python).
- [x] S1–S6: staging (21), procedures (8) and `fn_warehouse_operations` repointed. The three monitoring copies and
  that function list `raw.INFORMATION_SCHEMA.TABLES` once, and get the source from the table-name prefix.
  `q-check_scheduler_status` is limited to the Pancake tables in `raw`.
- [x] S7: `sql/migrations/raw_dataset_consolidation.sql`. Every scan carries a partition filter: all 31 tables set
  `require_partition_filter` (found by a BigQuery dry run). Dry runs pass for the freeze job check, the `__TABLES__`
  snapshot and one fingerprint compare; COPY and CREATE SCHEMA can't be dry-run before `raw` exists.
- [x] S8: `tests/test_raw_dataset_refs.py` (9 tests) passes.
- [x] S9: docs, AGENTS.md, sql/README.md, `.env.example`; manifest regenerated; the manifest builder maps unprefixed
  `raw.raw_*` tables to Pancake.
- [x] D1–D4 (lsoul_dbt): 7 source schemas, 34 `lsoul_raw_source` values, `deploy/cloudrun.sh` READER list
  (`raw`, `reportdb` plus routine-read datasets), deploy/README, docs; inventory regenerated.
- [ ] Not run: `validate_repo.py --imports` and the Pancake-order service tests. `.venv`'s Python 3.13 interpreter is
  missing and the system Python has no Flask/pandas.
- Pre-existing, not caused by this task: `stg_meta.stg_ads_reporting_my` reads a missing `stg_ads_reporting_my`
  table (only its dataset changed). `cloud-run-tiktok-thai-ads` still can't start.

## Phase 3b: Local validation, destination contract and monitoring (Build stage)

Planned 2026-11-06 from the prompt in @thread:thr_3atqcfzjdn. The objective, facts, decisions and boundaries
are in [the plan's continuation section](raw-dataset-plan.md#continuation-2026-11-06-local-validation-destination-contract-and-next-run-monitoring).
Everything is offline and mocked. `PY` means the test interpreter `$BB_THREAD_STORAGE/venv-raw/bin/python`.
The thread storage is `/Users/tony.pham/.bb/thread-storage/thr_dwipk8msx8`.
Test code never imports a `src/` module in the parent test process; each service case runs in its own
subprocess (see L4).

| Task | Scope | Depends on | Acceptance | Verify |
|---|---|---|---|---|
| L0 | **Test environment.** `uv venv --python 3.11` (fallback 3.12) at `$BB_THREAD_STORAGE/venv-raw`, then install the union of `src/cloud_run/*/requirements.txt`. No repo files change | none | `PY -c "import flask, pandas, pyarrow, google.cloud.bigquery, pandas_gbq, google.auth"` succeeds; interpreter and package versions are recorded | that command |
| L1 | **Graphify and AgentMemory.** AST-only graph of a scoped corpus copy under `$BB_THREAD_STORAGE/graphify/` (exclusions as in plan decision 9). Trace entry → fetch → transform → load → consumers for each source family. Read-only freshness check of the lsoul_dbt graph. AgentMemory: retrieval only | L0 | Every important graph finding is checked against the source and cited file:line; wrong destinations, duplicate loaders, env overrides and missed consumers are listed. Limitations (stale or AST-only graph, no memory records) are recorded in the verification record | `graphify query/path/explain` output, plus `rg` confirmation |
| L2 | **Destination contract.** `docs/raw-destination-contract.md`, linked from `docs/pipelines.md`. For each of the 30 services: folder, runtime entry point, source API/entity, country/account, the fully qualified table(s), config variables and precedence, HTTP and CLI paths, write disposition, schema/partition expectations, local/schema variants, scheduler (or `unknown`), file:line | L1 | Covers all 30 services and every table each writes. A totals section reconciles 30 services, the 31 live tables, and code-only/local-only/manual tables. VN vs TH TikTok and the Meta account tables stay distinct. The `pancake-order_returned`, Dianplus and Jushuitan findings are stated | `validate_repo.py` (links); reviewed against the plan's live inventory |
| L3 | **Fix the `tiktok-thai-ads` startup.** `app_runner.py` → `cr-tiktok-ads.py` (no renames). Remove the service from `KNOWN_BROKEN_SERVICES` in `scripts/validate_repo.py`. Update `tests/test_validate_repo.py` if it pins that entry. Update the known-issue lines in AGENTS.md, `docs/troubleshooting.md` and `docs/pipelines.md` (fixed locally; live still broken until deployed) | L0 | No missing-target warning or error for any service; the service imports in isolation and exposes `app` | `python3 scripts/validate_repo.py`; `PY scripts/validate_repo.py --imports`; `python3 -m unittest tests.test_validate_repo` |
| L4 | **Load-path harness, all 30 services.** Helper `tests/cloud_run_harness.py`. Each case runs in a subprocess with: dotenv disabled, sockets blocked, temp HOME/CLOUDSDK_CONFIG, synthetic env values (names from `.env.example`), and `bigquery.Client`/credentials stubbed. Test file: `tests/test_cloud_run_destinations.py`, with the expected mapping as **literals** | L2, L3 | For every service: (1) the fully qualified destination is `marine-cycle-484213-b4.raw.<table>`; (2) the `raw` default, with overrides set before import (`BQ_RAW_DATASET`; magento `BQ_PROJECT`/`BQ_DATASET`/`BQ_TABLE`; surfosm-inventory `BQ_DATASET`/`BQ_TABLE`/`GCP_PROJECT`) resolving as documented; (3) the existing write disposition and schema/field-addition options are unchanged; (4) `load_job.result()` is awaited; (5) when the load job raises, the caller gets a failure (an exception propagates, or the load function returns a failure value its caller acts on), never success. A service that falls short is fixed with a regression test when the retry is safe, or added to `READINESS_BLOCKERS` with an `expectedFailure` test that still asserts failure (plan decision 7). Documenting it alone doesn't pass. `pancake-order_returned` is pinned to `/orders` → `raw_order` | `PY -m unittest tests.test_cloud_run_destinations -v`; under system `python3` the cases are skipped and reported as skipped |
| L5 | **HTTP handlers, all 30 services.** `tests/test_cloud_run_routes.py`: the module's fetch function is stubbed to return synthetic records, `[]`, or raise. The Flask route is driven through `app.test_client()`. Magento's routes (it serves rather than exports) are covered too | L4 | Success: route OK and load called once with the right destination. Empty: the documented empty behaviour, with no load or an explicit valid-empty status. Fetch failure and load failure: non-2xx status, no load job after a fetch failure, and no rows-loaded claim in the response. The CLI `main()` path raises or exits non-zero, one case per service. A route or CLI that returns success on either failure is fixed with a regression test when the retry is safe (record the retry consequence in the contract), or added to `READINESS_BLOCKERS` with an `expectedFailure` test that still asserts non-success (plan decision 7). Documenting it alone doesn't pass | `PY -m unittest tests.test_cloud_run_routes -v` |
| L6 | **Fetch-level pagination and partial failure**, one representative service per family (Pancake, TikTok VN and TH, Meta, Dianplus, Jushuitan, Magento where it applies, Surfosm). `tests/test_cloud_run_fetch.py` stubs the HTTP client with synthetic pages | L4 | Multi-page responses are aggregated. A mid-page error yields non-success and no partial load job; otherwise it's fixed or blocked under plan decision 7. TH/VN tokens and account IDs route to their own tables | `PY -m unittest tests.test_cloud_run_fetch -v` |
| L7 | **Ambiguous items** (plan decisions 4–6). Dianplus: compare columns, and align `TABLE_ID` only if they describe the same entity. Jushuitan schema hunks: kept and reported. `pancake-order_returned`: decision recorded | L2 | Each item has evidence, the default taken, and the exact decision the owner needs | review the diff of the touched files |
| L8 | **Logging audit**, then a minimal structured log line only where destination, job ID or rows are missing, with no payloads or secrets | L4 | Every load path emits destination, job ID and loaded rows; fetched/transformed counts where they exist. Any added field has a test. The deploy-only caveat is stated | the L4/L5 tests assert the log line |

### Checkpoint E (after L0–L8)
- [ ] `PY -m unittest discover -s tests` passes. The skips under system `python3` are only the deps-gated service tests.
  *2026-11-06: every raw/service test passes on 3.11 and 3.13. The suite still has 44 failures, all in
  the warehouse-name modules from other in-flight work (no raw-dataset change in those functions; see the
  verification record). System `python3` skips 4 (the deps-gated suites).*
- [x] No assertion removed, no exclusion broadened, no unrelated behaviour changed (`git diff --stat` shows only L-task files plus the earlier P/S/D hunks).
- [x] Every fetch, load and mid-page failure case asserts non-success. Each case marked `expectedFailure` has a matching `READINESS_BLOCKERS` entry (service, behaviour, owner decision), and vice versa. The "expected failures" count equals the number of blocked cases. *(2 = 2, enforced by `ReadinessBlockers.test_blocker_map_matches_the_expected_failures`.)*

| Task | Scope | Depends on | Acceptance | Verify |
|---|---|---|---|---|
| L9 | **Required checks.** Review the `tests/test_raw_dataset_refs.py` guard and the migration inventory check; account for every active old-dataset reference (migration, rollback, archive and live only). Regenerate the manifest if sources changed. Recheck the earlier failures with fresh evidence: warehouse-name tests, the dbt `images` issue (core-pancake T1), the missing interpreter, service startup | L3–L8 | `python3 scripts/validate_repo.py`, `python3 -m unittest discover -s tests`, `PY -m unittest discover -s tests`, `python3 scripts/build_pipeline_manifest.py --check`, `python3 scripts/sql_index.py --check` and `PY scripts/validate_repo.py --imports` are run, each with exit code and counts. Passed, failed, skipped and blocked are reported separately | each command's exit code |
| L10 | **lsoul_dbt `dbt parse` only.** Use `uv run` and the repo's lock. `--target-path` and `--log-path` go under thread storage; temp HOME (no ADC). Check source schemas and the `lsoul_raw_source` provenance in the parsed `manifest.json` | L0 | Parse exits 0; every source in the 7 `src_*.yml` files has schema `raw`; no `lsoul_raw_source` names an old dataset. `compile`, `build` and `source freshness` are listed as pending live checks unless one is proven offline. The tracked `logs/dbt.log` and `graphify-out/` are unchanged | `git -C ../lsoul_dbt status --porcelain logs graphify-out` unchanged; parse exit code |
| L11 | **Static audit of `sql/migrations/raw_dataset_consolidation.sql`** (never executed) | L2 | 31/31 tables in each section; COPY keeps `_PARTITIONTIME`; every scan has a partition filter; the fingerprint compare and the `T_freeze` recheck are present; statement order matches the protocol; rollback reverses all 31. Findings are recorded | `python3 -m unittest tests.test_raw_dataset_refs`; manual review notes |
| L12 | **`docs/raw-dataset-next-run-monitoring.md`** for **2026-11-07 ICT**. Scenario A: no cutover, so services keep their live destinations. Scenario B: after an approved cutover. Read-only commands and Console steps for prompt items a–h: the scheduler inventory (discovered names and regions), the revision config through a safe allowlist (BQ_* names and values only, never full env dumps), Logs Explorer filters, `region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT` for LOAD jobs plus `bq show -j` for output rows, `INFORMATION_SCHEMA.PARTITIONS` freshness, partition-filtered counts with ICT/UTC conversion, old-destination writes, retry and duplicate risk, valid zero-row runs. Includes the per-service tracking table and verdict definitions (PASS, VALID EMPTY, FAILED, MISROUTED, NO INVOCATION, UNVERIFIED), a grace period (provisional), and the manual/unscheduled tables | L2, L8 | No command mutates anything. Dataform schedules are kept separate from ingestion schedules. The two documented 07:20 jobs are labelled unverified. Not every table is expected to change daily | `validate_repo.py` (links); review that every command is a read |
| L13 | **`tasks/raw-dataset-local-verification.md`**: commands run with real results; Graphify/AgentMemory use and limitations; local fixes and reasons; remaining failures and decisions; proposed durable lessons (not saved); the separate future cutover checklist (create/permission `raw`, pause writers, copy and verify, switch writers and consumers, resume, observe, keep rollback copies); one local-readiness verdict; separate production status. Also update `docs/pipelines.md` and `sql/README.md` where L2/L3 change facts | L9–L12 | Every claim cites a command or file:line. The verdict is `READY FOR CUTOVER REVIEW` only if `READINESS_BLOCKERS` is empty, no required check failed, and no in-scope service is still broken. Otherwise it is `NOT READY — <every blocker>`, which names each blocked service and its behaviour, each failed check and each unresolved defect (plan verdict rule). The record's blocker list matches `READINESS_BLOCKERS`. Nothing claims production is verified | `python3 scripts/validate_repo.py` |

### Checkpoint F (after L9–L13): hand back for Verify and Review. Deploy and migration remain separate user decisions.

**Build status (2026-11-06, offline, uncommitted).** Details are in
[raw-dataset-local-verification.md](raw-dataset-local-verification.md).
- [x] L0: thread-storage environments, CPython 3.11.10 and 3.13.15 (the repo `.venv` is still broken and was left unchanged).
- [x] L1: Graphify AST graph of a scoped copy (2,541 nodes); route → single-loader traces for 30/30 services. The dbt graph is stale; AgentMemory has 0 records.
- [x] L2: [../docs/raw-destination-contract.md](../docs/raw-destination-contract.md). 30 services → 29 tables (22 live, 7 code-only); 9 live tables have no Cloud Run writer.
- [x] L3: tiktok-thai-ads `app_runner.py` fixed; `KNOWN_BROKEN_SERVICES` emptied; regression test.
- [x] L4–L6: harness + 29 tests (12 + 10 + 7). Fetch-failure fixes in 12 services and empty-day fixes in 10. **2 readiness blockers** (Surfosm detail skip) as `expectedFailure`.
- [x] L7: Dianplus schema `TABLE_ID` aligned (same 85 columns); Jushuitan hunks kept; order_returned pinned. All recorded as decisions.
- [x] L8: job ID + project added to 15 success log lines (tested).
- [x] L9: `validate_repo` 0, `--imports` 30/30 (3.11 and 3.13), manifest regenerated and `--check` 0, `sql_index --check` 0, guard OK. The unittest suite has 44 failures from other work.
- [x] L10: `dbt parse` 0; 26 raw sources on `raw`; 34 provenance values on `raw`. compile/build/freshness pending live.
- [x] L11: migration audit, 31/31 forward and reverse. Gap: the fence doesn't cover project-level roles.
- [x] L12: [../docs/raw-dataset-next-run-monitoring.md](../docs/raw-dataset-next-run-monitoring.md) for 2026-11-07 ICT.
- [x] L13: verification record. Verdict **NOT READY**: the 2 Surfosm blockers plus the failing unittest suite (other work).

## Phase 4: Live (each task needs explicit user authorization; not run in Build)

| Task | Action | Depends on | Acceptance / verification |
|---|---|---|---|
| W1 | Inventory the writer set: Cloud Scheduler jobs, Cloud Run services and revisions, BigQuery load jobs by raw destination (30 days), service accounts | Checkpoint C | Every raw table maps to ≥ 1 known writer or is marked manual or none; the list is saved in the plan |
| W2 | Create `raw` (asia-southeast1); mirror ACLs (SA writers, `dbt-runner@` reader, reportdb callers) | W1 | `bq show --format=prettyjson raw` shows the expected ACL |
| R13 | Rehearsal in a scratch dataset pair: the full forward and rollback protocol with same-partition appends (cases a–d in the plan) | W2 | Fingerprints match both ways; the (b) write is detected; the (c) write is rejected; then drop the scratch datasets |
| W3 | Freeze: pause the writer set; check quiescence; record `T_freeze[t]` | R13 | 0 running jobs to raw destinations; `last_modified_time` stable ≥ 10 min |
| W4 | Final COPY of 31 tables; fingerprint compare; recheck `T_freeze` | W3 | 31/31 tables have equal `(p, n, x)`; no `last_modified_time` change (otherwise go back to W3) |
| W5 | Deploy services from `src/cloud_run/<svc>` | W4 | Each live revision has the new image and no `BQ_RAW_DATASET` override, or the override is `raw`. For `cloud-run-magento-order` and `cloud-run-surfosm-inventory`, check `BQ_DATASET` as well: a live `BQ_DATASET=magento`/`surfosm` would keep them on the old dataset (the fence would then make them fail) |
| W6 | Fence the old raw tables (revoke SA write access); resume the writer set **only after W7 and W10** | W5, W7, W10 | A scripted test write to one old table with a writer SA is denied |
| W7 | Deploy the repointed SQL objects: baseline old results, deploy, compare (repoint-sql-sources). This includes `reportdb.sp_stock_inventory_dashboard_daily` (editable copy added in Review; it reads `raw.raw_order` and `raw.raw_product_variations`). The 4 archived procedures that are still live and read old raw (`dianplus.sp_dianplus_core_inventory_insert`, `magento.sp_magento_core_order_insert`, `magento.sp_magento_core_order_item_insert`, `surfosm.sp_surfosm_core_order_item_insert`): W1 confirms nothing calls them; otherwise ask the user | W4 | Each function or procedure returns old = new for a fixed window |
| W10 | **Repoint the live Dataform repositories** (owner action in Dataform, outside both repos). 8 repositories read the old raw tables: `ppl-pancake`, `ppl-pancake-orders`, `ppl-tiktok`, `ppl-meta`, `ppl-dianplus`, `ppl-jushuitan`, `ppl-surfosm` (27 `head` definitions with `dataset:"raw_*"` declarations or `<old>.raw_*` provenance strings) and `ppl-magento`/`ppl-dianplus`/`ppl-jushuitan` declarations that omit `dataset` and inherit the repository default (`magento`, …). Set every raw declaration to `dataset:"raw"`, update the strings, compile, and release before the next scheduled run (daily 07:15–08:20 ICT) | W4 | Each repository compiles; its next run reads `raw.*` (job `referenced_tables`); no Dataform job reads an old raw table after cutover |
| W8 | dbt against `raw`: `dbt build` + `dbt source freshness` | W4, D1–D4 | Build passes; freshness reads `raw` |
| W9 | Observe the next scheduled run | W6 | New partitions in `raw.*` for each scheduled table; old `last_modified_time` = `T_freeze` |

### Checkpoint D: all success criteria in the plan are met; old tables kept, fenced, until the user approves retirement

## Phase 5: Cutover execution (2026-11-07)

Plan: [Cutover execution (2026-11-07)](raw-dataset-plan.md#cutover-execution-2026-11-07). Decisions U1–U8 are there.
Window: finish before 07:00 ICT Sunday 2026-11-08, with writers resumed by 06:30. Live steps are authorized by the user's
request and run only when their gate passes. A failed gate stops and asks through a form.
Offline checks for every code task: `python3 scripts/validate_repo.py`, `python3 -m unittest discover -s tests`
(failing IDs compared with the 44-failure baseline; any new failure blocks), `<test-python> scripts/validate_repo.py --imports`,
`python3 scripts/build_pipeline_manifest.py --check`, `python3 scripts/sql_index.py --check`.

### A. Code and inventory (offline, plus read-only live reads)

- [x] **A1. Inventory 31 → 32.** Add `jushuitan.raw_jushuitan_order` to `sql/migrations/raw_dataset_consolidation.sql`
  (copy, fingerprint, freeze and reverse sections) and to the guard test's expected set; fix the "31" mentions in the plan, checklist and runbook.
  - Acceptance: the guard test asserts exactly 32 `(old, raw)` pairs; the script's section counts all equal 32.
  - Verify: `python3 -m unittest tests.test_raw_dataset_refs`; `grep -c` per section.
  - Files: `sql/migrations/raw_dataset_consolidation.sql`, `tests/test_raw_dataset_refs.py`, `tasks/raw-dataset-local-verification.md`, `docs/raw-dataset-next-run-monitoring.md`.
- [x] **A2. Fix `dianplus-inventory` (U5).** Set a page size within the API limit (≤ 500). When Dianplus returns a non-success code or message,
  the HTTP route returns non-2xx and the CLI exits non-zero; "0 entries" is reserved for a real empty answer.
  Audit the other 3 Dianplus services for the same swallow and fix them the same way. Update the matching `local_run/` variant.
  - Acceptance: regression tests cover the API-error body → non-success, a legitimate empty page → valid empty, and pagination at the new page size.
  - Verify: focused unittest plus the standard checks.
  - Files: `src/cloud_run/cloud-run-dianplus-inventory/cr-*.py` (+ up to 3 sibling Dianplus services), `src/local_run/dianplus_inventory*.py`, `tests/…`.
- [x] **A3. Recover the 3 services with no repo source (U4).** For `pancake-orders-returned`, `jushuitan-inventory` and
  `meta-raw-ads-reporting-my`: fetch the deployed source (the Cloud Run source bucket `run-sources-266174294882-asia-southeast1`,
  or the live image's `/app` layer) into thread storage. Scan it for credentials first and never print a value. Add each as
  `src/cloud_run/cloud-run-<live-service-name>/` with `Dockerfile`, `requirements.txt`, `app_runner.py` and `cr-*.py`. Use the
  repo conventions: `os.getenv("BQ_RAW_DATASET", "raw")`, credentials from env vars and Secret Manager (create a secret through
  the BB secrets form only if no existing one fits), and non-success on fetch or load failure. Keep the live table name and columns.
  Leave the existing `cloud-run-pancake-order_returned` folder unchanged (decision D5).
  - Acceptance: each folder passes `validate_repo.py` wiring and the credential scan; mocked tests assert `raw.<live table>`, the override, and failure surfacing;
    the contract and `docs/pipelines.md` list them.
  - Verify: the standard checks plus `--imports`.
  - Files: 3 new folders (≤ 4 files each), `tests/test_cloud_run_services*.py`, `docs/raw-destination-contract.md`, `docs/pipelines.md`.
  - If a source can't be recovered: stop for that service and ask (fallback in the plan risks).
- [x] **A4. Reader inventory (read-only).** Find the readers of old raw tables over 30 days: `referenced_tables` by principal,
  `INFORMATION_SCHEMA.VIEWS`/`ROUTINES` in every dataset, Data Transfer scheduled queries. Diff the live routines against `sql/`
  (`sql_index.py --drift`).
  - Acceptance: a reader table in the verification record; each reader is marked repointed-in-C4 or owner-action.
- [x] **A5. Dataform scan and prepared edits (U2).** For all 11 repositories, read the files of the default workspace or the
  latest commit through the API. List every old raw declaration or reference, including declarations that inherit a default dataset.
  Prepare the edits in a new workspace `raw-cutover-20261107`: don't commit or push yet.
  - Acceptance: every hit is listed with file:line; a compile of the prepared workspace shows no old raw table in its dependencies.
- [x] **A6. dbt job wiring.** Find how `dbt-daily-build-trigger` gets its code (the Cloud Run job image, its build source and ref).
  Prepare a rebuild from `lsoul_dbt` `67e1539`.
  - Acceptance: the exact build and deploy command is recorded, plus the previous image digest for rollback.

### Checkpoint A: offline checks green (no new failures); A3 sources clean; A4–A6 lists complete

### B. Live preparation (no effect on current writers)

- [x] **B1. Runtime SA and grants (U3).** Create `lsoul-ingest-runner@`. Grant project `bigquery.jobUser`, `dataEditor` on `raw`
  only, and `secretAccessor` per secret. Grant `dataViewer` on `raw` to the readers from A4 (`dbt-runner@`, the Dataform agent, …).
  - Verify: `bq show --format=prettyjson raw`; `gcloud projects get-iam-policy` shows no Editor for the new SA.
- [x] **B2. Rehearsal (R13), with the new SA.** In a scratch pair, `zz_cutover_rehearsal_old` and `zz_cutover_rehearsal_raw`, run the full
  forward and rollback protocol, appending into the same partition (cases a–d). Add a write as the new SA to the scratch "old" dataset,
  which must be denied (the fence), and to the scratch "raw" dataset, which must succeed. Then drop the scratch datasets.
  - Acceptance: fingerprints equal in both directions; the case (b) write is detected; the case (c) write is denied.
- [x] **B3. SQL baselines.** Use the `repoint-sql-sources` skill: for each SQL object to repoint (repo `sql/` drift list plus A4 routines), save the
  current live definition and a fixed-window result (e.g. 2026-10-01 to 2026-11-06) to `sysdb` baseline tables or thread storage.

### Checkpoint B: rehearsal passed; SA permissions proven; baselines saved. Gate: it is before 23:00 ICT, otherwise ask

### C. Cutover window (2026-11-07 evening, done by 06:30 ICT on 2026-11-08)

- [x] **C1. Freeze.** Pause the 26 ingestion scheduler jobs and `dbt-daily-build-trigger`. Run migration Section 1: no running raw
  load jobs, and `last_modified_time` stable for ≥ 10 min. Record `T_freeze` in `sysdb.raw_cutover_freeze`.
- [x] **C2. Copy 32 tables and verify.** Run Sections 2–3: `CREATE TABLE raw.<t> COPY <old>.<t>` for all 32, compare the fingerprints, then
  recheck `T_freeze`. Any mismatch → back to C1.
  - Acceptance: 32/32 equal `(p, n, x)`; partitioning, clustering and `require_partition_filter` match the source.
- [x] **C3. Switch writers.** Deploy the 23 repo services plus the 3 recovered ones from `src/cloud_run/<folder>`, with
  `--service-account lsoul-ingest-runner@…` and `--remove-env-vars BQ_RAW_DATASET` (for magento and surfosm-inventory, also `BQ_DATASET`).
  Secrets stay unchanged. The Dianplus fix ships with it. Run 3–4 deploys in parallel; the canary `pancake-stats-product` goes first.
  - Acceptance: per service: Ready, 100% traffic on the new revision, the new SA, no dataset override, startup probe passed, and no ERROR.
    Record the previous revision as the rollback target.
- [x] **C4. Switch readers.** (a) Deploy the repointed SQL objects and compare old and new results against B3 for the fixed window.
  (b) Dataform: commit and push the workspace, then compile each release config and confirm no old raw dependency. (c) dbt: rebuild
  and deploy the job image from `67e1539`, then run the job once. It must pass and its `referenced_tables` must include `raw.*`
  and no old raw dataset.
  - Acceptance: every SQL object returns old = new; every Dataform release compiles clean; the dbt run succeeds and reads `raw`.
- [x] **C5. Live write proof and backfill (U5).** Run the authorized `dianplus-inventory` backfill for the missed 2026-11-06 window
  through the deployed service, with its CLI or route parameters for that window. It must load into `raw.raw_dianplus_inventory` as the new SA.
  Then confirm the fence: no old table's `last_modified_time` changed since `T_freeze`.
- [x] **C6. Resume.** Resume all 27 scheduler jobs.
  - Acceptance: `gcloud scheduler jobs list` shows all ENABLED, and the next run times are 2026-11-08 07:00–08:00.

### Checkpoint C: writers on `raw` through the new SA; readers on `raw`; old tables frozen. If anything is not done by 06:30, run the rollback protocol before 07:00

### D. Verify, document, ship

- [ ] **D1. First scheduled run (2026-11-08 07:00–08:30 ICT).** Use runbook scenario B: each scheduled table gets a load into `raw.*`,
  0 failed jobs, old tables unchanged, Dataform and dbt jobs read only `raw`, and `dianplus-inventory` loads a non-empty answer.
  If the flow ends before 07:00, this is recorded as pending, with the exact commands.
- [x] **D2. Docs.** Update `docs/pipelines.md`, `docs/raw-destination-contract.md`, AGENTS.md known issues, `docs/troubleshooting.md`,
  the runbook, `tasks/raw-dataset-local-verification.md` (the cutover record), and the plan status line.
- [ ] **D3. Git (U6).** Run `validate-changes`, review the diff for secrets and data, commit on `main` (only this task's files), and push.
- [ ] **D4. Graphify.** Build or refresh the AST graph for this repo (`graphify update`, no LLM): `src/`, `scripts/`, `tests/`,
  `docs/`, `sql/` text, excluding credentials, `.env`, `seeds/`, `data/` and notebooks. Refresh the `lsoul_dbt` graph if it is stale.
  Record where the graph lives.
- [ ] **D5. AgentMemory.** Save durable lessons (the user asked for it). Candidates: the raw dataset consolidation and its new SA;
  the dataset is read in a function default argument; the Dianplus page size limit is 500; Dataform repositories are hosted in Dataform, not Git;
  the dbt job image must be redeployed to change sources; the BigQuery MCP needs ADC re-auth when it reports `invalid_rapt`. No secrets.

### Checkpoint D: all Phase 5 acceptance met, or each gap reported with evidence; old tables kept until the user approves
