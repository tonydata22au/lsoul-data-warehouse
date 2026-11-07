# Raw-dataset consolidation: local verification record

Build stage, 2026-11-06 (ICT). Plan: [raw-dataset-plan.md](raw-dataset-plan.md), Phase 3b in
[raw-dataset-todo.md](raw-dataset-todo.md). Contract: [../docs/raw-destination-contract.md](../docs/raw-destination-contract.md).
Runbook: [../docs/raw-dataset-next-run-monitoring.md](../docs/raw-dataset-next-run-monitoring.md).

## Verdict

**Local readiness: NOT READY**, with these blockers:

1. `READINESS_BLOCKERS.surfosm_order_detail_skip`: cloud-run-surfosm-order skips orders whose detail request
   fails and loads the rest with HTTP 200 / exit 0 (`cr-surfosm-order.py:203-208`). Owner decision needed:
   fail the run, or report an explicit partial status.
2. `READINESS_BLOCKERS.surfosm_order_return_detail_skip`: the same in cloud-run-surfosm-order_return
   (`cr-surfosm-order_return.py:177-182`).
3. Required check failing: `python3 -m unittest discover -s tests` has **44 failures/errors** in the
   warehouse-name test modules. They come from other uncommitted work in this checkout and aren't caused by
   this change (evidence under [Checks](#checks)). It still has to be green, or explicitly waived by its
   owner, before a cutover review.

Every other in-scope item passed: all 30 services start, route to `marine-cycle-484213-b4.raw.<table>`,
honour their overrides, and surface fetch and load failures (12 services fixed here).

**Security (found in Review, 2026-11-06):** Dianplus ×4 and jushuitan-order printed their app secret, and
Jushuitan its access token, on **every run**. Cloud Logging keeps that output, so **rotate
`DIANPLUS_APP_SECRET` and `JUSHUITAN_APP_SECRET`** (and consider the Jushuitan token and app keys). That is an
owner action. The prints are removed locally (not deployed) and guarded by a test. Failure-path leaks of
Pancake `api_key`, Meta `access_token` and the Dianplus auth `appSecret` remain open. They are pre-existing
and need redaction in 16+ services (see [the contract](../docs/raw-destination-contract.md#findings-that-stay-open)).

**Production: unchanged.** No dataset was created, no table copied, nothing deployed, no SQL or Dataform
released, no scheduler, IAM or service touched. Live services keep their old destinations. Local mocks
prove nothing about production ingestion.

## Boundaries kept

Nothing called a source API, BigQuery, a service URL or Cloud APIs. Every service test ran in a subprocess
with sockets blocked, dotenv disabled, a temporary HOME (no ADC), dummy credential values, a fake
`bigquery.Client` and stubbed key loaders. `cloud-run-pancake-order` builds its key path from the repo root
(`cr-pancake-order.py:101`), and the harness's first probe intercepted one such call **without reading the
file**. Since then, every test points that path at a nonexistent file (as in the container) and asserts zero
key-file reads. No `.env` or `credentials/` content was read. `dbt parse` ran with a temporary HOME, telemetry
off, and target/log paths outside the repo; the tracked `logs/dbt.log` and `graphify-out/` didn't change.

**Concurrent work:** another session edited this checkout during the Build (16:00–16:40 ICT):
`scripts/pancake_candidate_sql.py`, `scripts/compare_pancake_repoint.py`,
`tests/test_table_function_call_args.py`, `sql/checks/*`, `sql/functions/reportdb.fn_order_product_inventory_summary.sql`.
Those aren't part of this change and weren't touched.

## Guidance, retrieval and tools actually used

| Item | Result |
|---|---|
| Orbyn harness `resolve --target <repo> --host claude` | Work mode not set. The prompt asks for simple in-place work, so this ran on `main` with no branches, worktrees or commits |
| Holistics blueprint (AGENTS.md, instruction.md, SKILL.md, holistics-problem-solving) | Read. Untools **Inversion** (UT-005) retrieved **live** from https://untools.co/inversion/ on 2026-11-06 and applied as the plan's failure → prevention → validation table |
| AgentMemory (MCP `memory_smart_search` / `memory_recall`) | Connected. 3 searches scoped to this task returned **0 records**. Nothing saved; the task documents are the continuity record |
| Graphify (`~/.claude/skills/graphify/SKILL.md`) | No graph for this repo. Built an **AST-only** graph (`graphify update`, no LLM, nothing uploaded) of a scoped copy in thread storage (`src/`, `scripts/`, `tests/`, editable SQL; no credentials, `.env`, CSV/JSON): 2,541 nodes, 5,611 edges, 263 communities. It traced all 30 routes to exactly one loader each; results below |
| Graphify, lsoul_dbt | The existing graph (2026-11-05 17:45) is **stale**: 45 model/test files are newer. Not rebuilt (its `graphify-out/` is tracked); lineage was checked with `dbt parse` instead |

Graph findings, each checked against the source:
- route → fetch → single load for all 30 services. Example: `cloud-run-surfosm-order` `run()` (L478)
  reaches `load_data_url_1`, `fetch_order_details` and one `insert_to_bigquery`. This supports the
  retry-safety argument (one load after all fetching), which the harness confirmed.
- 61 loader functions: 30 in `cloud_run/` and 31 in `local_run/` (`local_run/` has `meta_ads_my.py` and
  `tiktok_*_ad_group/campaign` writers with no Cloud Run counterpart).
- Duplicate writer: `cloud-run-pancake-order_returned` and `cloud-run-pancake-order` both reach a loader
  for `raw_order` (`cr-pancake-order.py:443` in both folders, plus the main service's `:591`).
- Limits: the AST graph has no table edges for SQL (106 SQL files give only file/FUNCTION nodes), and it
  can't see `app_runner.py`'s string path or destination literals. Consumers were therefore checked with
  `tests/test_raw_dataset_refs.py`, `sql_index.py --check` and `dbt parse`. Overrides and destinations were
  checked by the harness.

## Test environment

`uv` environments outside both repos: `$BB_THREAD_STORAGE/venv-raw` (CPython **3.11.10**, as in 28
Dockerfiles: Flask 3.1.3, pandas 3.1.1, pyarrow 26.0.1, google-cloud-bigquery 3.47.0) and `venv-raw313`
(CPython **3.13.15** with the pinned `cloud-run-pancake-order` requirements: pandas 3.0.5, bigquery 3.45.0,
plus pytz). The first install timed out reaching PyPI; a retry with `UV_HTTP_TIMEOUT=180` succeeded. The
repo's `.venv` is still broken (`python` → missing Homebrew 3.13) and was left unchanged.

## Local fixes and why

| Fix | Files | Reason / evidence |
|---|---|---|
| `app_runner.py` loads the existing `cr-tiktok-ads.py`; `KNOWN_BROKEN_SERVICES = {}` | `src/cloud_run/cloud-run-tiktok-thai-ads/app_runner.py`, `scripts/validate_repo.py` | The container couldn't boot (missing module). Regression test: `test_validate_repo.RepositoryChecks.test_every_app_runner_loads_an_existing_module` (RED before, GREEN after). `--imports` now passes for all 30 |
| A failed page, request error or API error code raises instead of `break`/`return []` | TikTok ×6, Dianplus ×4, `cr-jushuitan-order.py`, `cr-magento-order.py` | Outages were reported as **200 "0 entries found"**, and mid-run failures **loaded partial windows with 200** (probe + RED tests). Retry-safe: each service does its single load after all fetching |
| Empty source returns `("<message>", 200)` instead of `None` | 8 Pancake + 2 TikTok services | A valid empty day crashed the route with **500 "cannot unpack"** (RED test). This was a documented known issue left for a decision: flagged for owner review before deploy |
| Success log line includes `project.dataset.table [job_id]` | 15 services | Logs couldn't tie a run to its BigQuery job. Test: `RouteSuccess.test_success_logs_the_destination_job_id_and_rows` |
| `TABLE_ID = 'raw_dianplus_order_refund'` | `src/schema/bq-raw_dianplus..order_return.py` | Its 85 columns equal the refund loaders' in the same order; the old name matched no table or writer |
| Docs | AGENTS.md, `docs/troubleshooting.md`, `docs/pipelines.md`, `.agents/skills/run-pipeline/SKILL.md`, new contract and runbook | Known issues updated: fixed locally, not deployed |

Not changed, as AGENTS.md asks to note: `src/local_run/` and `src/csv_export/` variants keep the old
fetch-error handling and bare `return`s.

## Tests added

| File | What it proves | Result (3.11 and 3.13) |
|---|---|---|
| `tests/cloud_run_harness.py`, `tests/cloud_run_harness_child.py` | Isolated subprocess per service: gunicorn-style import through `app_runner.py`, fake BigQuery client, scripted HTTP, no key files | — |
| `tests/test_cloud_run_destinations.py` (14 tests) | Literal expected table per service (from the 2026-11-05 live inventory, not the code); fully qualified `raw` default; `BQ_RAW_DATASET` override (28); Magento `BQ_PROJECT`/`BQ_DATASET`/`BQ_TABLE`; surfosm-inventory `BQ_DATASET`/`BQ_TABLE`; `BQ_RAW_DATASET` ignored by those two; project from runtime ADC; `WRITE_APPEND`, field options, all-STRING; `.result()` awaited; failed load raises; client closed; no dataset created (only Meta creates a missing `raw`, in asia-southeast1); import-time key loads pinned | OK |
| `tests/test_cloud_run_routes.py` (10 tests) | Every service: route success = 2xx + one load to the expected table + the log line; valid empty = 2xx, no load; load failure, connection error and HTTP 500 = non-2xx, no rows-loaded claim, no load after a fetch failure; CLI success 0 / failures non-zero (29; Magento has no CLI) | OK |
| `tests/test_cloud_run_fetch.py` (9 tests) | Two-page aggregation for 17 services; a page-2 HTTP 500, connection reset or API error fails the run with **no load** (TikTok ×6, Dianplus ×4, Jushuitan, Magento including ALL mode, Pancake/Meta representatives, surfosm-inventory); TH/VN tables distinct; no credential value in any output or body; `READINESS_BLOCKERS` parity plus a pin of today's blocked behaviour | OK, **expected failures = 2** (the Surfosm blockers) |

Mutation check: with a VN table expected for tiktok-thai-ads, and `BQ_RAW_DATASET=raw_tiktok` injected
for tiktok-ads, `test_loads_append_to_the_raw_dataset` failed for both (2 failures). The tests can fail.

## Checks

Final run, 2026-11-06 ~16:45 ICT. Outputs are in thread storage (`F-*.txt`).

| Command | Exit | Result |
|---|---|---|
| `python3 scripts/validate_repo.py` | 0 after this record exists | Every static check PASS; no warnings (thai-ads warning gone) |
| `<venv 3.11>/bin/python scripts/validate_repo.py --imports` | 0 | `check_service_imports` PASS, **30/30** services |
| `<venv 3.13>/bin/python scripts/validate_repo.py --imports` | 0 | PASS, 30/30 |
| `python3 scripts/build_pipeline_manifest.py --check` | 0 | Regenerated after the service edits |
| `python3 scripts/sql_index.py --check` | 0 | 128 editable files, 0 problems |
| `python3 -m unittest tests.test_raw_dataset_refs` | 0 | 10 tests OK: no old-dataset reference in `src/`/editable SQL; the migration names exactly 31 tables |
| `python3 -m unittest discover -s tests` (system 3.15, no service deps) | 1 | 151 run, **44 failed/errored** (warehouse modules), **4 skipped** (the 3 service suites + pancake-order need deps) |
| `<venv 3.11> -m unittest discover -s tests` | 1 | 199 run, **44** failed/errored (same warehouse modules), 2 expected failures; every raw/service test passes |
| `<venv 3.13> -m unittest discover -s tests` | 1 | 199 run, same 44 + 2 expected failures |
| `git diff --check` (changed areas) | 0 | No whitespace errors |
| lsoul_dbt `dbt parse` (temporary HOME, target/logs in thread storage) | 0 | 26 raw source tables → `marine-cycle-484213-b4.raw` (4 `reportdb` sources unchanged); 34 `lsoul_raw_source` values all `raw.*` |

The **44 failures are not caused by this change.** They are in `test_warehouse_function_ids` (21),
`_overseas_names` (14), `_sales_names` (6), `_snapshot` (2) and `_inventory_names` (1). The diffs of all 21
functions they name contain **no** raw-dataset reference change; the only function this work touched,
`fn_warehouse_operations`, isn't among them. The assertions concern canonical warehouse names and live
snapshots (in-flight warehouse-identity work). `tasks/core-pancake-repoint-review.md:74` recorded 44
pre-existing failures; the count is unchanged.

**Blocked or pending (needs live access or authorization):** `dbt compile` (may query the warehouse),
`dbt build`, `dbt source freshness`. BigQuery dry runs of the repointed SQL against `raw`: the dataset
doesn't exist yet. Every live item in Phase 4 (W1–W10, R13).

**Earlier reported failures rechecked:**

| Item | Result |
|---|---|
| Warehouse-name tests | Same 44 failures, not from this change (above) |
| dbt `images` (core-pancake T1) | Marked done in `core-pancake-repoint-todo.md` with a live check on 2026-11-05. `dbt parse` passes now; not re-run live |
| Missing interpreter | The repo `.venv` is still broken; worked around with the thread-storage environments |
| Service startup | 30/30 import on 3.11 and 3.13, including tiktok-thai-ads |

## Migration script audit (`sql/migrations/raw_dataset_consolidation.sql`, not executed)

- 31 forward `CREATE OR REPLACE TABLE raw.<t> COPY <old>.<t>` and 31 reverse copies, with identical names
  and identical sets (Section 2 / Section 5). No `DROP`. `CREATE SCHEMA … location = 'asia-southeast1'`.
- COPY keeps `_PARTITIONTIME`. Fingerprints (`_PARTITIONTIME`, count, `BIT_XOR(FARM_FINGERPRINT(...))`)
  compare all 31 tables (Section 3), and `last_modified_time` freeze checks are present. Order follows the
  plan's protocol: create → freeze check → copy → verify → (deploy) → fence → rollback.
- **Gap:** the fence (Section 4) revokes `dataEditor` at **dataset/table** level with `<writer-sa>`
  placeholders. A writer service account with a **project-level** BigQuery role would bypass it. W1 must
  list the actual service accounts and their project-level roles before W6.

## Review stage (2026-11-06)

An independent read-only reviewer (a separate agent, given the code but not these conclusions) found
**no Critical issue** and 2 Required items, both in the runbook. A self-review then found the
every-run secret prints.

| Finding | Severity | Resolution |
|---|---|---|
| Dianplus ×4 / Jushuitan print the signing raw string (`APP_SECRET`) and unmasked request params (`app_id`, `app_key`, `access_token`, `sign`) on every run | Critical (pre-existing) | **Fixed** in `cloud_run/`. New test `MidRunFailure.test_fetch_output_never_contains_a_credential` scans the full output and body of every fetch scenario, with a distinct synthetic value per credential. It was RED with 25 failures before the fix and is GREEN after. Secrets must be rotated (owner) |
| Runbook tells operators to read logs that contain credentials | Required | **Fixed:** warning box, plus a redaction `sed` pipe on `gcloud logging read` |
| Runbook understated how old-code (scenario A) failures disguise themselves (Dianplus, Jushuitan and Magento too; partial windows meet PASS; fetch errors are prints, not ERROR) | Required | **Fixed:** fetch-error log search added; PASS now requires no fetch-error line; FAILED and VALID EMPTY rules updated |
| Failure-path credential echo (Pancake 12, Meta 2, Dianplus auth) | Required follow-up (pre-existing) | **Open:** recorded in the contract (finding 6), troubleshooting item 12 and the runbook warning. Needs redaction in each service; the harness can't detect it (no query string in fake URLs) |
| `expectedFailure` could fail for the wrong reason | Optional | **Fixed:** `test_blocked_behaviour_is_still_exactly_the_documented_one` pins today's behaviour (1 detail fails → exit 0, 1 row; all fail → exit 0, no load, "0 order details found") |
| Surfosm blocker text missed the `ok: false` skip and the all-details-fail → VALID-EMPTY look-alike | Optional | **Fixed** in the blocker map, contract and runbook |
| Meta create-dataset path untested; import-time key loads discarded; log assertion spread over lines | Optional / Nit | **Fixed:** `MissingDataset` tests (only Meta creates `raw`, in `asia-southeast1`); import-time key attempts recorded and pinned; log-line regex on one line |
| Runbook partition query treated `__UNPARTITIONED__` as "unpartitioned"; new-table check couldn't detect partitioning | Optional | **Fixed:** `partition_id IS NULL`, and `TABLES.ddl` checks |
| Contract said the Dianplus schema-script rename had no consequence | Optional | **Fixed:** the script now drops and recreates the live refund table if run |
| Incomplete VALID-EMPTY message list; the job-ID note ignored the 15 services that already logged it; pipelines.md `/health` vs `/healthz` and the thai-ads note; the troubleshooting intro contradiction | Nit | **Fixed** |
| Jushuitan `code != 0` now fails the run (same assumption as Dianplus); retry safety covers fetch failures only; thai-ads needs `TIKTOK_TH_ACCESS_TOKEN` live | FYI | Documented in the contract and decisions |

Checks after Review (thread-storage `review/`):
- `validate_repo.py`: 0, 10/10.
- `check_service_imports`: 30/30 on 3.11 and on 3.13.
- `manifest --check`: 0. `sql_index --check`: 0. `git diff --check`: 0.
- Change-scoped modules: **90 tests OK (2 expected failures)** on 3.11 and 3.13.
- Full suite on 3.11: 217 run, 44 failures/errors, **0 new** against the Build baseline (all `test_warehouse_*`).

## Mapping summary

30 services → 29 destination tables in `raw`: 22 live, 7 only in code. 9 live tables have no Cloud Run
writer. The full table, config precedence and failure behaviour are in the
[contract](../docs/raw-destination-contract.md#coverage-totals).

## Decisions for the owner

1. **Surfosm detail skip** (blockers 1–2): the fail-or-partial semantics.
2. **`cloud-run-pancake-order_returned`** fetches `/orders` into `raw_order`, a duplicate of pancake-order.
   Retire it, or port `local_run/pancake_orders_returned.py` (`/orders_returned` → `raw_orders_returned`)?
   Pinned as-is.
3. **Empty-day status change** (500 → 200) in 10 services: approve before deploying.
4. **Dianplus `resultCode` / Jushuitan `code` assumption:** a non-success code now fails the run. Confirm
   neither ever means "no data".
4a. **Rotate `DIANPLUS_APP_SECRET` and `JUSHUITAN_APP_SECRET`** (printed to Cloud Logging on every run by
   the deployed revisions), and decide on redacting the failure-path credential echo in the Pancake, Meta
   and Dianplus auth paths.
5. **`bq-raw_jushuitan..order.py`** extra hunks (`REQUIRE_PARTITION_FILTER=False`, credential path):
   restore the HEAD values?
6. **External consumers:** Dataform `ppl-*` repositories (W10), Looker Studio and scheduled queries still read
   the old datasets. Local edits don't change them.
7. **Uncommitted state:** this change and the other in-flight work share one working tree; stage only the
   intended hunks when committing.

## Future cutover checklist (separate; each step needs authorization)

1. W1: inventory writers (scheduler jobs and their `httpMethod`, Cloud Run services, revisions, service
   accounts and **project-level** roles, LOAD jobs by destination for 30 days).
2. W2: create `raw` in `asia-southeast1` and mirror ACLs (writer SAs, `dbt-runner@`, `reportdb` callers).
   Rehearse in a scratch pair (R13).
3. W3: pause every writer and confirm quiescence (no running jobs, `last_modified_time` stable ≥ 10 min).
   Record `T_freeze`.
4. W4: run Sections 2–3: copy 31 tables, compare fingerprints, recheck `T_freeze`.
5. W5: deploy the services from `src/cloud_run/<svc>`. Confirm the image and `BQ_RAW_DATASET`/`BQ_DATASET`
   per revision.
6. W7 + W10 + W8: deploy the repointed SQL (old = new baseline), release Dataform on `raw`, run dbt.
7. W6: fence the old tables (including project-level grants), then resume the writer set.
8. W9: observe the next runs with the [runbook](../docs/raw-dataset-next-run-monitoring.md) (scenario B).
9. Keep the old tables fenced as rollback copies until the owner approves retiring them (Section 5 is the
   rollback path).

## Proposed durable lessons (not saved)

1. LSOUL Cloud Run services read their BigQuery dataset in a function default argument, so an env
   override must be set before import (tests) and applies only to new revisions (operations).
2. In this repo, a fetch loop that `break`s on an error turns outages into "0 entries found" 200s. Test
   failure paths at the HTTP level, not only the happy path.
3. Graphify's AST graph has no SQL table edges here; use `dbt parse` and the reference guard for consumer
   lineage.

## Deploy 2026-11-06 night

Plan: [raw-dataset-deploy-plan.md](raw-dataset-deploy-plan.md). Code: commit `2b372f2` (local, on top of
`82fac76`), deployed 19:15–21:40 ICT with `gcloud run deploy <service> --source src/cloud_run/<folder>
--update-env-vars <override> --update-secrets <env>=<secret>:latest` (project `marine-cycle-484213-b4`,
region `asia-southeast1`). Canary `pancake-stats-product` first, then the rest after a form gate.

**Credentials moved to Secret Manager.** The live images had their credentials baked in; the repo code reads
env vars. The user supplied the values through BB's secrets form (never seen by the agent). Ten secrets
were created (`tiktok_vn_access_token`, `tiktok_th_access_token`, `meta_access_token`, `dianplus_app_key`,
`dianplus_app_secret`, `jushuitan_app_key`, `jushuitan_app_secret`, `magento_username`, `magento_password`,
`surfosm_api_key`), each with a per-secret `secretAccessor` grant for the Cloud Run service account, like
the existing `pancake_pos`.

**Verified per service:** Ready; 100% traffic on the new revision; new image; the destination override equals
the dataset it loaded this morning (BigQuery job metadata, 2026-11-06 07:00–07:16 ICT); the secret references
match; no other env vars; startup probe passed; no ERROR or traceback lines. The only log noise is gunicorn's
"Control server error" in the two Python 3.13 images, which the previous revisions also logged.

| Service | Previous revision (rollback target) | New revision | Destination override | Secrets |
|---|---|---|---|---|
| `cr-tiktok-ads` | `cr-tiktok-ads-00002-cwx` | `cr-tiktok-ads-00003-fkz` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_vn_access_token` |
| `cr-tiktok-reporting-basic-auction-ad` | `cr-tiktok-reporting-basic-auction-ad-00003-4mz` | `cr-tiktok-reporting-basic-auction-ad-00004-sg2` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_vn_access_token` |
| `cr-tiktok-thai-ads` | `cr-tiktok-thai-ads-00003-6jn` | `cr-tiktok-thai-ads-00004-52j` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_th_access_token` |
| `cr-tiktok-thai-gmv-max-report` | `cr-tiktok-thai-gmv-max-report-00001-x2w` | `cr-tiktok-thai-gmv-max-report-00002-lnc` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_th_access_token` |
| `cr-tiktok-thai-reporting-basic-auction-ad` | `cr-tiktok-thai-reporting-basic-auction-ad-00001-dxd` | `cr-tiktok-thai-reporting-basic-auction-ad-00002-g87` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_th_access_token` |
| `dianplus-inventory` | `dianplus-inventory-00004-9zq` | `dianplus-inventory-00005-zk6` | `BQ_RAW_DATASET=dianplus` | `dianplus_app_key`, `dianplus_app_secret` |
| `dianplus-order` | `dianplus-order-00006-52f` | `dianplus-order-00007-lst` | `BQ_RAW_DATASET=dianplus` | `dianplus_app_key`, `dianplus_app_secret` |
| `dianplus-order-refund` | `dianplus-order-refund-00001-m5s` | `dianplus-order-refund-00002-g2g` | `BQ_RAW_DATASET=dianplus` | `dianplus_app_key`, `dianplus_app_secret` |
| `dianplus-product` | `dianplus-product-00004-xpg` | `dianplus-product-00005-dlp` | `BQ_RAW_DATASET=dianplus` | `dianplus_app_key`, `dianplus_app_secret` |
| `jushuitan-order` | `jushuitan-order-00017-l97` | `jushuitan-order-00018-rxc` | `BQ_RAW_DATASET=jushuitan` | `jushuitan_app_key`, `jushuitan_app_secret` |
| `magento-order` | `magento-order-00002-4sp` | `magento-order-00003-qdm` | `BQ_DATASET=magento` | `magento_username`, `magento_password` |
| `meta-raw-ads-reporting-a` | `meta-raw-ads-reporting-a-00006-fx6` | `meta-raw-ads-reporting-a-00007-t5k` | `BQ_RAW_DATASET=raw_meta` | `meta_access_token` |
| `meta-raw-ads-reporting-ecom` | `meta-raw-ads-reporting-ecom-00004-fcr` | `meta-raw-ads-reporting-ecom-00005-zfg` | `BQ_RAW_DATASET=raw_meta` | `meta_access_token` |
| `pancake-customer` | `pancake-customer-00007-m6t` | `pancake-customer-00008-zrs` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `pancake-inventory-histories` | `pancake-inventory-histories-00002-dvh` | `pancake-inventory-histories-00003-xx4` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `pancake-order` | `pancake-order-00014-knk` | `pancake-order-00015-wd8` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `pancake-product-variations` | `pancake-product-variations-00008-qfw` | `pancake-product-variations-00009-ww4` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `pancake-stats-inventory-variations` | `pancake-stats-inventory-variations-00003-jmg` | `pancake-stats-inventory-variations-00004-jht` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `pancake-stats-product` | `pancake-stats-product-00001-m89` | `pancake-stats-product-00002-ljq` | `BQ_RAW_DATASET=raw_pancake` | `pancake_pos` |
| `surfosm-inventory` | `surfosm-inventory-00002-6h9` | `surfosm-inventory-00003-p9r` | `BQ_DATASET=surfosm` | `surfosm_api_key` |
| `surfosm-order` | `surfosm-order-00003-jvt` | `surfosm-order-00004-cst` | `BQ_RAW_DATASET=surfosm` | `surfosm_api_key` |
| `surfosm-order-return` | `surfosm-order-return-00002-6qj` | `surfosm-order-return-00003-nb2` | `BQ_RAW_DATASET=surfosm` | `surfosm_api_key` |
| `tiktok-gmv-max-report` | `tiktok-gmv-max-report-00001-l7j` | `tiktok-gmv-max-report-00002-lrz` | `BQ_RAW_DATASET=raw_tiktok` | `tiktok_vn_access_token` |

**Not deployed (unchanged):** `pancake-orders-returned` (decision D5; its live code writes `raw_orders_returned`,
unlike the repo copy), and `jushuitan-inventory` and `meta-raw-ads-reporting-my` (no source in this repo).

**Rollback, per service:** `gcloud run services update-traffic <service> --region asia-southeast1 --project
marine-cycle-484213-b4 --to-revisions <previous revision>=100`.

**Found during the inventory:** `jushuitan.raw_jushuitan_order` exists and loads daily. The 2026-11-05
inventory missed it, so the future migration has 32 tables, not 31. No load arrived this morning from
`pancake-product-variations`, `dianplus-order-refund` or `meta-raw-ads-reporting-ecom`; check those first
on 2026-11-07.

**Risks after the deploy (review, 2026-11-06 night):**
- **Rotation ends the rollback window.** The previous revisions run images with the old credentials baked in.
  After a credential is rotated, rolling that service back fails authentication, so roll forward instead.
  Rotate only after the 2026-11-07 runs succeed.
- **The old images still contain credentials.** Every family's previous images in Artifact Registry
  (TikTok VN/TH, Meta, Magento, Surfosm, Pancake, Dianplus, Jushuitan) hold their credentials. Rotate all of
  them once the new revisions are proven, then delete the old images and revisions (owner action). Git
  history has no hardcoded credentials in `src/` (checked every commit).
- **The values typed tonight are unverified** until the 07:00 runs. A wrong value shows up as an auth
  failure (fix it with a new secret version, or roll back before rotating).
- **The Cloud Run service account has project-level `roles/editor`,** which is broad. Consider a dedicated
  least-privilege account.
- **The remote doesn't have the deployed code.** Commits `2b372f2` and `7af11f4` are local only
  (`origin/main` is behind production).

**Next for the owner:**
1. Watch the 2026-11-07 07:00–07:16 ICT runs ([runbook](../docs/raw-dataset-next-run-monitoring.md),
   scenario C).
2. Once they succeed, rotate the credentials in the vendor consoles and add each new value as a new secret
   version; the next cold start reads `latest`.

## Cutover 2026-11-07

Plan: [Cutover execution (2026-11-07)](raw-dataset-plan.md#cutover-execution-2026-11-07) (decisions U1–U8, from the owner
through in-thread forms). Executed by the Build stage of @thread:thr_ssazbmz9k4 as `ops.data@lsoul.com`, 14:35–15:15 ICT.
All times ICT.

**Result: every raw table lives in `marine-cycle-484213-b4.raw`; every scheduled writer and every active reader uses it.**
The old tables are frozen in place as rollback copies (kept until the owner approves retiring them, U7).

| Step | What ran | Evidence |
|---|---|---|
| Pre-check | 2026-11-07 07:00 runs: 21 tables loaded, 0 failed jobs. No load from 4 services: `dianplus-inventory` (API error swallowed; see A2), `pancake-product-variations`, `dianplus-order-refund`, `meta-raw-ads-reporting-ecom` | One authorized read-only call: the Pancake variations API answered `success: true`, 0 rows for 2026-11-06 (4,467 variations in total), so VALID EMPTY |
| A1–A3 (code) | 32-table inventory; Dianplus fails on API errors, inventory page size 500; 3 live services recovered into the repo (`cloud-run-pancake-orders_returned`, `cloud-run-jushuitan-inventory`, `cloud-run-meta-ads-reporting-my`). Each recovered archive matched its live image digest via Cloud Build; its hardcoded credentials hash-matched the existing secrets (values never printed) and were replaced by env vars | Commits `8a32786`, `1253788`; tests: 0 new failures against the 46-failure baseline; `--imports` passes |
| B1 | Created SA `lsoul-ingest-runner@`: project `bigquery.jobUser`; WRITER on dataset `raw`; `secretAccessor` on 11 secrets. `raw` ACL also gets READER `dbt-runner@` | `gcloud projects get-iam-policy` shows only `bigquery.jobUser` for it |
| B2 | Rehearsal on scratch datasets (dropped afterwards): copy, fingerprint equal; a write after the copy detected by `last_modified_time`; **as the new SA, a load into the "old" dataset was denied** and into "raw" (same partition) succeeded; reverse copy equal, no duplicates | Fingerprint mismatches 0 / 0; case c `Access Denied: Dataset`; case d exit 0 |
| C1 | Paused all 27 scheduler jobs (26 ingestion + `dbt-daily-build-trigger`). Query 1a: 0 running raw loads. `T_freeze` in `sysdb.raw_cutover_freeze`: 32 tables, 7,778,866 rows, newest write 07:16 | — |
| C2 | `CREATE OR REPLACE TABLE raw.<t> COPY <old>.<t>` × 32 (14:43) | Section 3: **0 mismatching partitions of 3,484**; query 1c: 0 rows; 7,778,866 rows in `raw`; partitioning DAY ingestion-time on all 32, `require_partition_filter` as the source (31 true, `raw_jushuitan_order` false) |
| C3 | Deployed 26 services from `src/cloud_run/<folder>` with `--service-account lsoul-ingest-runner@…`, removed `BQ_RAW_DATASET`/`BQ_DATASET` (code default `raw`); secrets unchanged (3 recovered services got their secret refs); `jushuitan-inventory` keeps Direct VPC egress | 26/26: Ready, 100% traffic on the new revision, new SA, no dataset override; no ERROR logs |
| C4a | Repointed live SQL (live DDL with only the dataset qualifier changed): `core_pancake.sp_core_order_insert`, `reportdb.sp_stock_inventory_dashboard_daily`, and 7 views (`stg_pancake.stg_customer`, `stg_inventory_histories`, `stg_order`, `stg_orders_returned`, `stg_stats_inventory_variations`, `stg_variations`; `jushuitan.stg_jushuitan_taobao_tmall_order_manual`). Pre-cutover definitions: `sql/archive/zarchived-*.pre-raw-cutover-20261107.sql` | Dry runs passed; afterwards only 2 live routines still name old raw tables, both already broken (below) |
| C4b | Dataform: `ppl-pancake` (4 declarations) and `ppl-pancake-orders` (2) changed `dataset:"raw_pancake"` → `"raw"` in workspace `raw-cutover-20261107`; committed and pushed to `main` (`65b17ab3c3`, `3ac6d407b4`); release configs compiled from `main` and set as the current release | 0 compilation errors; every declaration resolves to `raw`; no old raw dataset in the compiled graph |
| C4c | dbt: created `raw.raw_orders_returned_history` (728 rows, assertion passed); deployed `lsoul_dbt` main as `lsoul-dbt:67e1539b3459`, then `212b04995c38` (fix: the `not_null` test had moved onto the nullable `images` column); full refresh of `core_pancake__variations` and `core_pancake__orders_returned`; granted `dbt-runner@` WRITER on `mart` and READER on `google_ads` (steps of `deploy/cloudrun.sh apply` that didn't run because it stops at the deleted dataset `core_meta`) | Full refresh (`dbt-daily-build-d2fbp`): models built; the only failure was the misplaced test, fixed in `212b049`. First daily build failed on the missing `mart` grant (`-s88kf`). **Daily build `dbt-daily-build-mpg5x` (15:11–15:14): PASS=152, ERROR=0**; its 130 jobs read only dataset `raw` (no old raw dataset). Freshness (logged, not fatal) flags `raw_dianplus_order_refund` and `raw_product_variations` as stale after their empty days |
| C5 | Authorized backfill: `GET /` on `dianplus-inventory` (VN yesterday = 2026-11-06, the missed window) at 15:08 | HTTP 200; LOAD job by `lsoul-ingest-runner@` into `raw.raw_dianplus_inventory`, 297 rows, partition 2026-11-07, schema unchanged (13 columns). **Fence on a real table:** as the new SA, a load into `raw_pancake.raw_order` was denied (`Access Denied: Dataset`); query 1c still 0 rows. The temporary Token Creator grant used for these tests was removed |
| C6 | Resumed the 26 ingestion scheduler jobs, then `dbt-daily-build-trigger` after the dbt build passed; first runs 2026-11-08 07:00–08:00 | 27 ENABLED, identical to the states recorded before the freeze |

### Rollback targets

| Service | Folder | Previous revision (rollback target; compute SA, old dataset) | New revision (lsoul-ingest-runner@, `raw`) |
|---|---|---|---|
| `pancake-stats-product` | `cloud-run-pancake-stats_product` | `pancake-stats-product-00002-ljq` | `pancake-stats-product-00003-jkf` |
| `cr-tiktok-ads` | `cloud-run-tiktok-ads` | `cr-tiktok-ads-00003-fkz` | `cr-tiktok-ads-00004-wbn` |
| `cr-tiktok-reporting-basic-auction-ad` | `cloud-run-tiktok-reporting-basic-autction-ad` | `cr-tiktok-reporting-basic-auction-ad-00004-sg2` | `cr-tiktok-reporting-basic-auction-ad-00005-v2j` |
| `cr-tiktok-thai-ads` | `cloud-run-tiktok-thai-ads` | `cr-tiktok-thai-ads-00004-52j` | `cr-tiktok-thai-ads-00005-w9w` |
| `cr-tiktok-thai-gmv-max-report` | `cloud-run-tiktok-thai-gmv-max-report` | `cr-tiktok-thai-gmv-max-report-00002-lnc` | `cr-tiktok-thai-gmv-max-report-00003-9f4` |
| `cr-tiktok-thai-reporting-basic-auction-ad` | `cloud-run-tiktok-thai-reporting-basic-autction-ad` | `cr-tiktok-thai-reporting-basic-auction-ad-00002-g87` | `cr-tiktok-thai-reporting-basic-auction-ad-00003-xh6` |
| `tiktok-gmv-max-report` | `cloud-run-tiktok-gmv-max-report` | `tiktok-gmv-max-report-00002-lrz` | `tiktok-gmv-max-report-00003-g9s` |
| `dianplus-inventory` | `cloud-run-dianplus-inventory` | `dianplus-inventory-00005-zk6` | `dianplus-inventory-00006-gqv` |
| `dianplus-order` | `cloud-run-dianplus-order` | `dianplus-order-00007-lst` | `dianplus-order-00008-5jn` |
| `dianplus-order-refund` | `cloud-run-dianplus-order-refund` | `dianplus-order-refund-00002-g2g` | `dianplus-order-refund-00003-x9t` |
| `dianplus-product` | `cloud-run-dianplus-product` | `dianplus-product-00005-dlp` | `dianplus-product-00006-g8z` |
| `jushuitan-order` | `cloud-run-jushuitan-order` | `jushuitan-order-00018-rxc` | `jushuitan-order-00019-tcb` |
| `magento-order` | `cloud-run-magento-order` | `magento-order-00003-qdm` | `magento-order-00004-mg5` |
| `meta-raw-ads-reporting-a` | `cloud-run-meta-ads-reporting-a` | `meta-raw-ads-reporting-a-00007-t5k` | `meta-raw-ads-reporting-a-00008-6ld` |
| `meta-raw-ads-reporting-ecom` | `cloud-run-meta-ads-reporting-ecom` | `meta-raw-ads-reporting-ecom-00005-zfg` | `meta-raw-ads-reporting-ecom-00006-596` |
| `pancake-customer` | `cloud-run-pancake-customer` | `pancake-customer-00008-zrs` | `pancake-customer-00009-tdx` |
| `pancake-inventory-histories` | `cloud-run-pancake-inventory_histories` | `pancake-inventory-histories-00003-xx4` | `pancake-inventory-histories-00004-952` |
| `pancake-order` | `cloud-run-pancake-order` | `pancake-order-00015-wd8` | `pancake-order-00016-db7` |
| `pancake-product-variations` | `cloud-run-pancake-product_variations` | `pancake-product-variations-00009-ww4` | `pancake-product-variations-00010-spv` |
| `pancake-stats-inventory-variations` | `cloud-run-pancake-stats_inventory_variations` | `pancake-stats-inventory-variations-00004-jht` | `pancake-stats-inventory-variations-00005-jqv` |
| `surfosm-inventory` | `cloud-run-surfosm-inventory` | `surfosm-inventory-00003-p9r` | `surfosm-inventory-00004-5gz` |
| `surfosm-order` | `cloud-run-surfosm-order` | `surfosm-order-00004-cst` | `surfosm-order-00005-t9w` |
| `surfosm-order-return` | `cloud-run-surfosm-order_return` | `surfosm-order-return-00003-nb2` | `surfosm-order-return-00004-5qp` |
| `pancake-orders-returned` | `cloud-run-pancake-orders_returned` | `pancake-orders-returned-00001-lbs` | `pancake-orders-returned-00002-krb` |
| `jushuitan-inventory` | `cloud-run-jushuitan-inventory` | `jushuitan-inventory-00001-v7l` | `jushuitan-inventory-00002-llx` |
| `meta-raw-ads-reporting-my` | `cloud-run-meta-ads-reporting-my` | `meta-raw-ads-reporting-my-00005-fjc` | `meta-raw-ads-reporting-my-00006-jbr` |

Rollback order (plan, "Rollback"): pause the 27 scheduler jobs; Section 5 of the migration script (reverse copy
`raw` → old, verify); route each service to its previous revision (`gcloud run services update-traffic <svc>
--region asia-southeast1 --project marine-cycle-484213-b4 --to-revisions <previous>=100`); redeploy the archived SQL
definitions; in Dataform, revert the two cutover commits and recompile the releases; set the dbt job image back to
`lsoul-dbt:4f7c66407258` (lsoul_dbt commits deployed: `67e1539`, `212b049`). The previous revisions run as the compute SA (project Editor), so they can write the old
tables again.

### Found during the cutover (not changed)

- `reportdb.fn_warehouse_operations` already fails: it scans dataset `core_meta`, which no longer exists. Not redeployed
  (the repo file adds `raw` but still reads `core_meta`). **2026-11-07 follow-up:** the repo file now scans `core`,
  `stage` and `mart` and no longer scans the deleted datasets `core_meta`, `core_tiktok`, `dataform`, `stg_meta` and
  `stg_tiktok` (`sql/monitoring/looker_studio_*` regenerated). BigQuery dry run of the `CREATE OR REPLACE TABLE
  FUNCTION` passed. Not deployed yet; deploying needs the owner's go-ahead.
- `jushuitan.sp_jushuitan_core_inventory_insert` already fails validation (`jushuitan.stg_jushuitan_inventory` doesn't
  exist) and hasn't been called in 30 days. Only its provenance strings name the old table. Not redeployed.
  **2026-11-07 follow-up:** superseded by dbt `core.core_jushuitan__inventory`; the repo file moved to
  `sql/archive/zarchived-jushuitan.sp_jushuitan_core_inventory_insert.sql`. The live procedure is left in place.
- Six Dataform repositories listed in the plan (`ppl-tiktok`, `ppl-meta`, `ppl-dianplus`, `ppl-jushuitan`,
  `ppl-surfosm`, `ppl-magento`) last ran on 2026-11-05 and no longer exist; dbt replaced them.
- `lsoul_dbt/deploy/cloudrun.sh apply` stops at its grant step for `core_meta` (deleted); its `ROUTINE_READ_DATASETS`
  still lists `core_meta` and `core_tiktok`. Owner fix in lsoul_dbt. **2026-11-07 follow-up:** lsoul_dbt `c0b393f`
  makes the grant step skip a dataset that `bq show` reports as Not found (other errors still stop `apply`), tested in
  `c519487`, narrowed to `Not found: Dataset` in `913f303`; not pushed.
- Ad hoc readers of old raw tables (30 days): `khuongduyle291@gmail.com` (queries on `raw_pancake`), `holistics@`
  (INFORMATION_SCHEMA metadata only). They now see frozen data unless repointed. Looker Studio sources can't be
  listed from BigQuery; owner check.
- `00_WORKING/content.sql` (Dataform scratch file) reads `dianplus.raw_dianplus_inventory`; unscheduled.
