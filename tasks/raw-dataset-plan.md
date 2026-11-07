# Plan: consolidate every raw table into one BigQuery dataset `raw`

Tasks: [raw-dataset-todo.md](raw-dataset-todo.md). Status: Build stage done offline on 2026-11-06 (Phases 1–3, uncommitted). Nothing live has run: no dataset, copy, deploy or SQL deploy.
Continuation planned on 2026-11-06: [local validation, destination contract and next-run monitoring](#continuation-2026-11-06-local-validation-destination-contract-and-next-run-monitoring) (Phase 3b in the todo).
Phase 3b built on 2026-11-06 (offline, uncommitted). Local verdict **NOT READY** (2 Surfosm readiness blockers, plus 44 unittest failures from other work); see [raw-dataset-local-verification.md](raw-dataset-local-verification.md).

**Cutover executed on 2026-11-07 (14:35–15:15 ICT):** all 32 raw tables are in `raw`; every scheduled writer and active reader uses it. [Plan section](#cutover-execution-2026-11-07), [record](raw-dataset-local-verification.md#cutover-2026-11-07). First scheduled runs on `raw`: 2026-11-08 07:00 ICT.

## Objective

Move every raw table (written by the Python loaders) into one dataset,
`marine-cycle-484213-b4.raw` (location `asia-southeast1`), so raw data lives in one place.
Cloud Run services must keep appending to those tables without breaking, and every
downstream reader must read from `raw.*`. That covers repo SQL, the dbt project
`lsoul_dbt` (@project:proj_3598auxu2c, `/Users/tony.pham/Downloads/lsoul_dbt`) and the
reportdb functions/procedures.

## Live inventory (read on 2026-11-05 through per-dataset `INFORMATION_SCHEMA.TABLES`)

31 raw base tables. **No table-name collisions** when they are merged:

| Current dataset | Tables |
|---|---|
| `raw_pancake` (whole dataset is raw) | raw_customer, raw_inventory_histories, raw_order, raw_orders_returned, raw_product_variations, raw_stats_inventory_variations, raw_stats_product |
| `raw_tiktok` (whole dataset is raw) | raw_tiktok_ad_group, raw_tiktok_ads, raw_tiktok_campaign, raw_tiktok_gmv_max_report, raw_tiktok_reporting_basic_auction_ad, raw_tiktok_reporting_basic_auction_campaign, raw_tiktok_thai_ad_group, raw_tiktok_thai_ads, raw_tiktok_thai_campaign, raw_tiktok_thai_gmv_max_report, raw_tiktok_thai_reporting_basic_auction_ad |
| `raw_meta` (whole dataset is raw) | raw_ads_reporting_a, raw_ads_reporting_ecom, raw_ads_reporting_my |
| `dianplus` (mixed; also holds core tables) | raw_dianplus_inventory, raw_dianplus_order, raw_dianplus_order_refund, raw_dianplus_product |
| `jushuitan` (mixed) | raw_jushuitan_inventory, raw_jushuitan_taobao_tmall_order_manual |
| `magento` (mixed) | raw_magento_order |
| `surfosm` (mixed) | raw_surfosm_inventory, raw_surfosm_order, raw_surfosm_order_return |

Code and docs also reference raw tables that **do not exist live**: `jushuitan.raw_jushuitan_order`,
`raw_pancake.raw_product`, `raw_variations`, `raw_ecom_product`, `raw_stats_order`,
`raw_stats_inventory_product`, `raw_warehouse_transfers_completed`, `raw_purchase`,
`raw_transaction`, `raw_orders_returned_history`. Their writers are repointed to `raw`
like the rest, and they get created on first load as they would today.

## Architecture decisions

1. **Keep table names unchanged** (`raw.raw_order`, `raw.raw_dianplus_order`, ...). No names
   collide, column names and write dispositions stay the same, and the change is limited to the
   dataset qualifier. Renaming tables to source-prefixed names such as `raw.pancake__order` would
   be a separate, larger change and is left as an open question.
2. **Copy, don't recreate.** Use `CREATE TABLE raw.<t> COPY <old>.<t>` (or `bq cp`). This keeps the
   schema, ingestion-time partitioning (`_PARTITIONTIME`), clustering and data. Never use the
   destructive `src/schema/*` scripts for the move.
3. **Keep the old tables, fenced read-only, during a rollback window.** Once the move is verified, rename or expire
   them later, only with explicit user approval. Don't drop them in this task.
4. **Make the dataset configurable with a `raw` default.** Each Cloud Run service reads an optional
   `BQ_RAW_DATASET` env var, defaulting to `"raw"`. Rollback then means setting one env var or
   redeploying the previous revision, with no code change. Each service folder stays self-contained;
   no shared module is added. `cr-magento-order.py` already reads `BQ_DATASET`; only its default
   changes.
5. **Freeze-based lossless cutover; no time-based delta.** Rows appended before and after a copy
   can share one ingestion-time partition, so `_PARTITIONTIME`/load time can't separate them.
   The plan therefore **stops all writers, then makes one final copy of a quiescent source.**
   See [Cutover and rollback protocol](#cutover-and-rollback-protocol).
6. **Access.** Grant `raw` the same writers (Cloud Run runtime service accounts) and readers
   (`dbt-runner@`, reportdb callers, Looker or other consumers) as the source datasets. Copy the
   ACLs from `raw_pancake` and the mixed datasets.

## Scope by repository

| Area | Files (approx.) | Change |
|---|---|---|
| `src/cloud_run/*` | 30 | Default dataset → `os.getenv("BQ_RAW_DATASET", "raw")`. Same in the Meta `create_dataset_if_not_exists` path |
| `src/local_run/*` | 31 | Dataset literal → `raw` (keep variants in sync, per AGENTS.md) |
| `src/schema/*` | 32 | Dataset → `raw` (edit only; never run them for the move) |
| `sql/staging`, `sql/procedures`, `sql/functions`, `sql/ad_hoc`, `sql/checks`, `sql/monitoring`, `sql/source_provenance.json` | ~40 | `` `marine-cycle-484213-b4.<old>.raw_*` `` → `` `marine-cycle-484213-b4.raw.raw_*` ``. `sql/live/` and `sql/archive/` are not edited |
| `raw_pancake.INFORMATION_SCHEMA` / `sp_check_partition_insert_dates` / `partition_insert_dates_*` | few | Point the partition checks at `raw` |
| docs, metadata, scripts, tests | ~7 | `docs/pipelines.md`, `docs/architecture.md`, `sql/README.md`, AGENTS.md/troubleshooting mentions, `metadata/pipeline_manifest.json` (regenerated), `validate_repo.py` and tests that assert dataset names |
| New | 1–2 | `sql/migrations/raw_dataset_consolidation.sql` (create dataset, quiescence check, final COPY, per-partition fingerprint compare, fence and reverse-copy statements), plus a test asserting no `src/` or editable `sql/` file references an old raw dataset |
| `lsoul_dbt` | ~40 | `models/raw/*/src_*.yml` `schema:` → `raw` (7 files); `lsoul_raw_source` meta strings (~33); `deploy/README.md` ACL list; docs. That repo already has unrelated uncommitted changes: edit only these lines and keep them |

## Commands

- Offline: `python3 scripts/validate_repo.py`, `python3 -m unittest discover -s tests`,
  `.venv/bin/python scripts/validate_repo.py --imports`, `python3 scripts/build_pipeline_manifest.py --check`,
  `python3 scripts/sql_index.py --check`, `rg -n -e "$OLD" -e "$OLD_PY" src` and `rg -n -e "$OLD" sql --glob '!sql/live/**' --glob '!sql/archive/**' --glob '!sql/migrations/raw_dataset_consolidation.sql'` (expect none; `OLD`/`OLD_PY`/`EXCLUDE` are defined in the todo). The migration script is checked separately: its old references must equal the 31-table inventory.
- dbt (lsoul_dbt): `dbt parse` and `dbt compile` (offline-ish; they need the profile). `dbt build` needs authorization.
- BigQuery dry runs (`dry_run: true`) of every edited SQL object after `raw` exists.
- **Authorization required, each specific action:** creating dataset `raw` and copying 31 tables,
  granting ACLs, deploying 25+ Cloud Run services (`gcloud run deploy`, outside repo paths),
  deploying edited functions/procedures, pausing and resuming schedulers, fencing the old tables, the scratch-dataset rehearsal, a smoke run of one service.

## Success criteria

- [ ] `raw` exists in `asia-southeast1` with all 31 tables, and the per-partition fingerprint `(n, digest)` equals the frozen source for every table.
- [ ] The rehearsal (R13) proves no missing or duplicate rows in both directions, with appends into the same partition.
- [ ] No editable code or SQL references `raw_pancake.`, `raw_tiktok.`, `raw_meta.`, `<source>.raw_*` or a bare old dataset literal in Python. Excluded: `sql/live/`, `sql/archive/` and the cutover script `sql/migrations/raw_dataset_consolidation.sql`. A unit test enforces it.
- [ ] The cutover script names exactly the 31 old inventory tables, each paired with `raw.<t>`; the same unit test checks it.
- [ ] Every Cloud Run service writes to `raw.<same table name>` by default, overridable by `BQ_RAW_DATASET`; offline checks and `--imports` pass.
- [ ] After deploy, the first scheduled (or one authorized) run of each service appends rows to `raw.*` with no new table auto-created with a drifted schema.
- [ ] Repointed reportdb functions/procedures return identical results old vs new for a fixed date window (the repoint-sql-sources baseline method).
- [ ] lsoul_dbt `dbt parse`/`compile` succeed with sources on `raw`; `dbt build` (authorized) passes and source freshness reads `raw`.
- [ ] Old tables remain untouched until the user approves their retirement.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Rows land in old tables between the copy and the deploy | High (silent data loss in `raw`) | Freeze writers and check quiescence, then a final copy, fingerprint equality and a `last_modified_time` recheck; fence the old tables after the switch (protocol steps 1–5) |
| A service writes to `raw` before its table is copied, so BigQuery auto-creates a table with an autodetected schema | High | Deploy only after the protocol step 3 verification passes for all 31 tables |
| Writer set incomplete (unknown schedulers or manual loads) | High | W1 inventories Cloud Scheduler jobs, Cloud Run invocations and BigQuery load jobs by destination for 30 days; the fence turns any missed writer into a loud failure |
| Missing IAM on `raw` for Cloud Run SAs or `dbt-runner@` | High (loads fail) | Mirror the ACLs first; verify with `bq show --format=prettyjson raw` |
| Deployed services not in the repo, or deploy commands pointing outside the repo (known issue) | Med | Inventory live services first (`gcloud run services list`, authorized); deploy from `src/cloud_run/<svc>` |
| BigQuery scheduled queries, views, Looker Studio or other consumers outside the repos still read old datasets | Med | Keep the old tables during the rollback window; list scheduled queries and dashboards (authorized) |
| **The live Dataform repositories (8 `ppl-*`, scheduled 07:15–08:20 ICT) declare the old raw datasets** and are edited outside both repos | **High** (staging, core and reportdb silently go stale: writers fill `raw` while Dataform keeps reading the frozen old tables) | Task W10: repoint and release every repository before resuming writers (protocol step 5) |
| The repointed SQL is deployed after writers resume | High (staging reads frozen tables; `sp_*_insert` loads only when the newest partition is today) | W7 and W10 are prerequisites of W6 |
| `cloud-run-tiktok-thai-ads` cannot start (known issue) | Low | Repoint the code anyway; report it as still broken |

## Cutover and rollback protocol

**Definitions.** For a table `t`, the *fingerprint* is a per-partition multiset digest:

```sql
SELECT _PARTITIONTIME AS p, COUNT(*) AS n,
       BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x  -- order-independent row digest
FROM `marine-cycle-484213-b4.<ds>.<t>` AS t GROUP BY p
```

`n` is included because BIT_XOR cancels exact duplicate pairs. Two tables are **equal** when
every `(p, n, x)` matches; `_PARTITIONTIME` is preserved by table COPY. The *writer set* is every
Cloud Scheduler job, other trigger and manual loader that appends to a raw table. W1 lists them;
only two schedulers are documented today. *Quiescent* means: every trigger in the writer set is
paused, no BigQuery job with a raw destination is `PENDING`/`RUNNING` (from
`region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`, or `bq ls -j -a`), and each table's
`last_modified_time` is unchanged across two reads at least 10 minutes apart (longer than the
longest observed run).

**Forward cutover (one maintenance window, outside 07:00–09:00 ICT):**

1. **Freeze.** Pause the writer set, wait for quiescence, and record each source table's
   `last_modified_time` as `T_freeze[t]`. Manual loaders (the Jushuitan Taobao/Tmall manual import)
   are told not to run.
2. **Final copy.** `CREATE OR REPLACE TABLE raw.<t> COPY <old>.<t>` for all 31 tables. It reads the
   frozen source, so there is no delta.
3. **Verify forward.** Fingerprint(old) = fingerprint(raw) for every table. Re-read every old
   `last_modified_time` and confirm it still equals `T_freeze[t]`, so no write slipped in during the
   copy. On any mismatch, go back to step 1. Nothing has been deployed yet.
4. **Switch writers.** Deploy the services (default `raw`). Confirm each live revision's env var
   and image before resuming.
5. **Switch readers, then fence.** Deploy the repointed SQL (W7) and release the repointed Dataform
   repositories (W10), so every reader uses `raw` before any new rows arrive there. Then remove write
   access to the old raw tables for the Cloud Run service accounts (table-level IAM in the mixed
   datasets; dataset ACL for `raw_pancake`, `raw_tiktok`, `raw_meta`), so a stray old writer fails
   loudly. Then resume the writer set.
6. **Verify after cutover.** After the next run, new partitions appear in `raw.<t>`. The old
   `last_modified_time` still equals `T_freeze[t]`.

**Rollback (reverse reconciliation before old readers or writers resume):**

1. Pause the writer set again and wait for quiescence on `raw`.
2. Check that `raw.<t>` ⊇ the frozen old table: for every partition p, the old `(n, x)` equals raw's
   `(n, x)` restricted to the rows copied at freeze. In practice the old `last_modified_time`
   equals `T_freeze[t]`, and fingerprint(old) matches the step-3 record.
3. `CREATE OR REPLACE TABLE <old>.<t> COPY raw.<t>`. This carries rows written only to `raw` after
   cutover back to the old table. Verify fingerprint(old) = fingerprint(raw).
4. Restore the old write access, set `BQ_RAW_DATASET=<old dataset>` (or redeploy the previous
   revisions), revert the SQL, Dataform (W10) and dbt changes, resume the writer set.

**Proof (rehearsal before production, task R13).** In a scratch dataset pair, use an
ingestion-time-partitioned table and run the protocol with appends into the **same partition**:
(a) before the copy; (b) between freeze and copy, which must be impossible or detected by the
`last_modified_time` check; (c) to the old table after the switch, which must be rejected by the
fence; (d) to `raw` after the switch. Run rollback and show fingerprint equality in both
directions, with no missing or duplicate rows (equal `n` per partition plus equal digest).

## Working-tree coordination (checked 2026-11-05)

- The checkout has other uncommitted, in-flight work: reportdb function edits, the core-pancake
  repoint (`tasks/core-pancake-repoint-*.md`; procedures moved to `sql/archive/`, new
  `sp_pancake_core_variations_insert.sql`) and warehouse-name tests. This task edits only the
  dataset qualifier on the lines it owns and stages only its own hunks. The SQL counts above come from
  the current tree: 8 procedures, 21 staging files, 1 function. Before each S-task, re-run the sweep,
  because the in-flight work can add or archive files.
- The leftover-reference sweep uses two patterns (see the todo): `OLD` for qualified references, and
  `OLD_PY` for bare dataset literals in Python. The bare-literal form covers the 11 dianplus,
  jushuitan, magento and surfosm writers that `OLD` alone misses.
- Orbyn harness: work mode is not set and the run is unattended, so per the harness this is treated
  as `isolated` and nothing is saved. Agent Flow assigns the project checkout, so Build edits in place
  and preserves the unrelated changes.

## Open questions (defaults used unless the user overrides)

1. Table naming in `raw`: keep current names (default) or rename to source-prefixed names?
2. When should the old tables and datasets be retired (`raw_pancake`, `raw_tiktok`, `raw_meta`), after how many days? Default: keep them; retire later on request.
3. Any consumer outside these two repos (Looker Studio, scheduled queries, notebooks) that must be repointed?

## Continuation (2026-11-06): local validation, destination contract and next-run monitoring

Source: the execution prompt in @thread:thr_3atqcfzjdn (final output). Tasks: Phase 3b (L0–L13) in
[raw-dataset-todo.md](raw-dataset-todo.md#phase-3b-local-validation-destination-contract-and-monitoring-build-stage).
Scope is **local only**. The Build above stays uncommitted; nothing is deployed or migrated.

### Objective

**Problem.** The data-warehouse owner needs to review a cutover. The consolidation change is implemented
but not verified: no service import or load-path test has run, and one service can't start. So a cutover
review can't rely on it yet, and the operator has no checklist for the next scheduled run.

**Done means:** all 30 Cloud Run services are proven, with mocks, to write
`marine-cycle-484213-b4.raw.<existing table>` and to honour their documented overrides. The required
offline checks pass, or each failure is reported with evidence. A dated runbook exists for the next run.
All of this stays inside the boundary below.

Deliverables: one authoritative service-to-table contract, focused fixes and regression tests,
`tasks/raw-dataset-local-verification.md`, `docs/raw-dataset-next-run-monitoring.md`, a separate future
cutover checklist, and one verdict: `READY FOR CUTOVER REVIEW` or `NOT READY — <blockers>`. Production
migration and deployment status is reported separately; local mocks never verify production.

### Facts established in Plan (read 2026-11-06; Build re-verifies before relying on them)

- **30 service folders.** 28 take the dataset from `os.getenv("BQ_RAW_DATASET", "raw")` as a **function
  default argument**. That default is evaluated at import, so an override must be set before import.
  - `cloud-run-magento-order` reads `BQ_PROJECT`, `BQ_DATASET` and `BQ_TABLE` (`cr-magento-order.py:58-60`).
  - `cloud-run-surfosm-inventory` reads `BQ_DATASET` and `BQ_TABLE` (`cr-surfosm-inventory.py:44-45`), and
    takes its project from `GCP_PROJECT`/`GOOGLE_CLOUD_PROJECT` (`:293`).
- **`cloud-run-tiktok-thai-ads` can't start.** `app_runner.py:4` loads `cr-tiktok-thai-ads.py`, but the folder
  only has `cr-tiktok-ads.py`. That file writes `raw_tiktok_thai_ads` with `TIKTOK_TH_ACCESS_TOKEN`
  (`:39`, `:201`). The Dockerfile runs `app_runner:app`. `scripts/validate_repo.py` lists the service in
  `KNOWN_BROKEN_SERVICES`.
- **`cloud-run-pancake-order_returned` fetches the wrong entity.** `cr-pancake-order.py:259,443` fetches
  ordinary `/orders` into `raw_order`; it is a copy of `pancake-order`. The returned-orders pipeline is
  `src/local_run/pancake_orders_returned.py:55,306`: `/orders_returned` into `raw_orders_returned`.
  Changing only the service's destination would put ordinary orders into `raw_orders_returned`.
- **Dianplus refund vs return naming.** The loaders write `raw_dianplus_order_refund` (cloud `:550`,
  local `:560`), which is the live table name. The schema script `bq-raw_dianplus..order_return.py:22`
  names `raw_dianplus_order_return`.
- **Jushuitan schema script has extra edits.** `src/schema/bq-raw_jushuitan..order.py` differs from HEAD
  in more than its dataset:
  - `REQUIRE_PARTITION_FILTER` changed from `True` to `False`.
  - The `GOOGLE_APPLICATION_CREDENTIALS` fallback is gone; the key path is now the repo-root `credentials/`.

  Every other schema file changes only its dataset line. `raw_jushuitan_order` is not live.
- **Python environments.** `.venv/bin/python` points to a missing Homebrew 3.13, so it can't run. Available:
  `uv` 0.12.21 and `python3.12`. The Dockerfiles use `python:3.11-slim`.
- **lsoul_dbt.** `graphify-out/` and `logs/dbt.log` are tracked; `target/` is ignored. Versions: dbt-core
  1.12.6 and dbt-bigquery 1.12.1, with an oauth (ADC) profile.
- **Graphify.** This repo has no graph. The lsoul_dbt graph is from 2026-11-05 17:45, before the D1–D4 edits,
  so treat it as stale until checked.
- **AgentMemory.** The MCP server is connected, but three searches scoped to this task returned no records.
  The task documents are the continuity record.
- **Schedules.** Only `pancake-insert-raw_order` and `pancake-insert-raw_product_variations` (07:20 ICT) are
  documented (`docs/pipelines.md:13`), and they are not verified live. All other ingestion schedules are
  unknown.
- **Runbook date.** The current date is 2026-11-06 ICT, so the runbook targets **2026-11-07 (Saturday) ICT**.

### Method

The primary method is Untools **Inversion** (UT-005, https://untools.co/inversion/, retrieved live on
2026-11-06). Pre-mortem: "the cutover failed; why?" Issue Trees (UT-002) handle any service that fails the
harness. Imagined failures are hypotheses to test, not findings.

| Failure condition | Prevention → validation |
|---|---|
| A service writes the wrong dataset, table, entity or account | Expected mapping written as literals in the test, from the live inventory and the contract, never from code constants → mocked load asserts the fully qualified destination |
| An override is ignored or has a different precedence than documented | Subprocess per case, with env set **before** import → assert the resolved destination |
| A service can't start after deploy | `--imports` smoke test, plus a test that each `app_runner.py` target exists |
| A fetch or load failure is reported as a successful ingestion | Mocked fetch error and mocked `load_job.result()` raise → assert a non-success outcome (route non-2xx; CLI raises or exits non-zero). A service that swallows either is fixed (decision 7) or added to `READINESS_BLOCKERS`, which forces `NOT READY` |
| A reader still uses an old dataset | `tests/test_raw_dataset_refs.py` guard, plus a check that dbt's parsed manifest puts every source schema on `raw` |
| Tests pass because nothing ran | Sockets blocked; assert the mocks were called with the expected arguments; count skipped tests separately |
| The operator can't tell whether tomorrow's run worked | Runbook correlates scheduler → revision → request → job → table, with a verdict per service |

### Decisions (defaults for this unattended run; each is reported at handoff)

1. **Work in place.** Edit on `main` in both repos, with no branches, worktrees, commits or pushes; the
   prompt asks for simple in-place work, which overrides the harness's unattended `isolated` default.
   Preserve all unrelated uncommitted work, including core-pancake repoint, warehouse names and dbt edits.
2. **Test environment outside both repos.** Create `$BB_THREAD_STORAGE/venv-raw` with `uv`, Python 3.11 to
   match the Dockerfiles (3.12 as fallback). Install the union of the services' `requirements.txt`. Leave
   `.venv` alone. Package downloads are allowed; test runs block sockets.
3. **Fix the clear startup defect only.** Point `cloud-run-tiktok-thai-ads/app_runner.py` at the existing
   `cr-tiktok-ads.py` and keep all deployed filenames. Remove the service from `KNOWN_BROKEN_SERVICES`
   (the validator flags it once fixed). Update the known-issue lines in AGENTS.md and the troubleshooting
   and pipeline docs: fixed locally, still broken live until deployed.
4. **`pancake-order_returned`: keep the current behaviour** (`/orders` → `raw_order`) and pin it with a test.
   Porting the returned-orders logic would change a deployed service's business behaviour and needs the
   owner's decision. That decision is open but doesn't block the consolidation: the destination semantics
   are unchanged. The verdict lists it.
5. **Dianplus schema script.** Compare its columns with the refund loader. If they describe the same entity,
   align `TABLE_ID` to `raw_dianplus_order_refund` (the script is edited only, never run). Otherwise record
   the mismatch.
6. **Jushuitan schema hunks: keep them.** Who made them is unknown. Report the HEAD values as a decision.
7. **Failure surfacing gates readiness.** A fetch failure or a load failure (`load_job.result()` raises, or the
   job reports errors) must produce a non-success outcome: a non-2xx route status, and a raised exception or
   non-zero exit on the CLI path. It must never produce a success response or a claim that rows loaded. For
   each service that falls short:
   - **Fix it, with a focused regression test, when the retry is safe and the fix is in scope.** Retry-safe
     means a Cloud Scheduler retry can't append duplicates: the request issues one load job, or every failure
     path happens before any load job commits. A failed BigQuery load job appends nothing. The fix changes
     only the error path (status code, exception propagation); the success path, destination, write
     disposition and columns stay unchanged. Each fixed service's retry consequence is recorded in the
     contract and in runbook item f.
   - **Otherwise, block it.** For example: the request runs several load jobs and an earlier one may already
     have committed, or the fix needs a business or idempotency decision. The service goes into a named
     `READINESS_BLOCKERS` map in the test module, with the service, the observed behaviour and the owner
     decision needed. The verification record mirrors that map. The service's failure-case test **still
     asserts non-success** and is marked `unittest.expectedFailure`. The assertion stays, the count appears as
     "expected failures", and a later fix shows up as an unexpected success.
   - **Documenting a swallowed failure never satisfies acceptance.** Any entry in `READINESS_BLOCKERS` forces
     the verdict `NOT READY — <service: behaviour>`. No assertion is removed or weakened to get green tests.
8. **Logging.** Audit first: does each load path log destination, job ID and rows? Change nothing if they all
   do. Otherwise add a minimal one-line structured log, with no payloads or secrets, only where it's missing,
   plus a test. Those fields exist only after deploy.
9. **Graphify.** Build the AST-only graph (`graphify update`, no LLM, nothing uploaded) for a scoped corpus
   copied under `$BB_THREAD_STORAGE/graphify/`: `src/`, `scripts/`, `tests/`, the docs. Exclude credentials,
   `.env`, `seeds/`, `data/`, logs and notebooks. Check the lsoul_dbt graph's freshness read-only; don't
   rewrite its tracked `graphify-out/`. Verify every graph finding against the source and cite file:line.
10. **dbt.** Run `dbt parse` only, with `--target-path` and `--log-path` under thread storage so the tracked
    `logs/dbt.log` isn't touched. Use a temporary HOME (no ADC) and no warehouse access. Mark `compile`,
    `build` and `source freshness` pending unless one is proven offline.
11. **AgentMemory.** Save nothing. Propose durable lessons at handoff.

### Boundaries

- **Allowed:** read and edit local files; create an isolated test environment; offline checks and mocked
  tests with synthetic fixtures; prepare read-only monitoring commands and SQL for later.
- **Not allowed:** Cloud Run deploys, image pushes or builds; any BigQuery dataset or table
  create/copy/replace/delete; IAM, scheduler or Dataform changes; calling service URLs; running ingestion,
  exporters, backfills or schema scripts; any dbt run, build or freshness check against production; reading
  `.env`, `credentials/`, tokens or customer data. Pipeline `--dry-run` flags still call source APIs, and
  importing a module or running `--help` can have side effects. Read the code first.

### Success criteria (Phase 3b)

- [ ] The contract lists all 30 services and every table each one writes, with:
  - fully qualified destination, configuration variables and their precedence
  - HTTP and CLI paths, write disposition and schema/partition expectations
  - local/schema variants and scheduler (evidenced or `unknown`), with file:line references

  Coverage totals reconcile the 30 services with the 31 live tables and the code-only tables.
- [ ] Mocked tests pass for every service:
  - import, and a fully qualified destination with the `raw` default
  - override precedence, write disposition, and an awaited `.result()`
  - fetch failure and load failure through the HTTP route return non-success (non-2xx, no rows-loaded
    claim), and the CLI path raises or exits non-zero
  - a legitimate empty response is a distinct valid-empty success, with no load job
  - one pagination or partial-failure test per source family; a mid-page error is non-success with no partial load
  - each case that doesn't meet this is either fixed under decision 7 with a regression test, or listed in
    `READINESS_BLOCKERS` with an `expectedFailure` test that still asserts non-success
- [ ] These pass, or each failure is listed with output: `validate_repo.py`, unittest, `build_pipeline_manifest.py --check`, `sql_index.py --check`, and `validate_repo.py --imports` with the test Python.
- [ ] `dbt parse` succeeds and every raw source resolves to schema `raw`. Live-only dbt checks are listed as pending.
- [ ] The migration script is audited statically (31 tables, partition preservation, verification, order) and never executed.
- [ ] The local-verification record and the monitoring runbook exist, with:
  - the explicit date 2026-11-07, scenarios A and B
  - copyable read-only commands
  - the per-service tracking table
  - verdict definitions: PASS, VALID EMPTY, FAILED, MISROUTED, NO INVOCATION, UNVERIFIED
- [ ] The handoff ends with one evidence-backed local-readiness verdict and a separate production status.
  **Verdict rule:** `READY FOR CUTOVER REVIEW` only if `READINESS_BLOCKERS` is empty, no required check failed,
  and no in-scope service is still broken. Otherwise the verdict is `NOT READY — <every blocker>`: each
  `READINESS_BLOCKERS` entry, each failed required check, and each unresolved startup or routing defect.


## Cutover execution (2026-11-07)

Source: the user's request in @thread:thr_ssazbmz9k4 ("start the migration and fully deploy, make sure everything
works perfectly"), continuing @thread:thr_zxeivhttts. Tasks: [Phase 5 in the todo](raw-dataset-todo.md#phase-5-cutover-execution-2026-11-07).
This section supersedes the Phase 4 W-task order where they differ. The protocol, fingerprint and rollback above
still apply unchanged.

### Live facts read in Plan (2026-11-07 13:55–14:15 ICT, read-only `bq`/`gcloud`)

- **Dataset `raw` already exists** in `asia-southeast1` (created 2026-11-06 23:48 ICT), **with 0 tables**. Its ACL is the
  project defaults (projectWriters/Owners/Readers, owner `ops.data@lsoul.com`).
- **Today's 07:00 runs:** 21 raw tables loaded, 0 failed load jobs. No load for 4 scheduled services:
  - `dianplus-inventory`: **swallowed API error.** The Dianplus API answered `系统处理异常:分页数不能超过500!`
    ("page size cannot exceed 500"). The service sends `pageSize 2000`, logged "0 entries found" and returned 200, so
    today's inventory is missing. This is a regression: before the 2026-11-06 deploy it loaded.
  - `pancake-product-variations`: "Successfully fetched 0 variations" for the 2026-11-06 window. `dianplus-order-refund` and
    `meta-raw-ads-reporting-ecom`: the API returned 0 rows. No error was logged, so these are VALID EMPTY until shown
    otherwise. Build checks whether `pancake-product-variations` ever loads on an ordinary day (3rd consecutive empty day).
- **The inventory is 32 tables:** the 31 listed in the plan, plus `jushuitan.raw_jushuitan_order`, which loads daily. The migration script and
  guard test still name 31 (`raw_jushuitan_order` count 0 in both).
- **Writer set (Cloud Scheduler, `asia-southeast1`):** 26 HTTP jobs to Cloud Run (all at 07:00–07:15 Asia/Saigon), plus
  `dbt-daily-build-trigger` (08:00, a Cloud Run job). All 26 services run as `266174294882-compute@developer`, which
  holds project `roles/editor`.
- **Dataform:** 11 repositories, all in `asia-southeast1`; no other location has any. Only `ppl-pancake` and
  `ppl-pancake-orders` match the plan's `ppl-*` list. `ppl-tiktok`, `ppl-meta`, `ppl-dianplus`, `ppl-jushuitan`,
  `ppl-surfosm` and `ppl-magento` do not exist live. The others (`ppl-reports`, `ppl-manual-data_insert`, `ppl-AI`,
  `00_WORKING`, `ai_*`, `LSOUL_Category_Share_Report`, …) must be scanned for old raw references. Only
  `opsdatalsoul/lsoul_document` is Git-linked.
- **dbt:** `lsoul_dbt` `main` = `origin/main` = `67e1539` already declares sources on `raw`. Today's production run
  (dbt-runner, after 07:30) still read `raw_pancake`, `raw_tiktok`, `raw_meta`, `dianplus`, `jushuitan`, `magento`, `surfosm`,
  so the job runs an older image or ref. Redeploying it is part of the cutover.
- **Credentials:** the BigQuery MCP's ADC token needs re-authentication (`invalid_rapt`). `bq`/`gcloud` work as
  `ops.data@lsoul.com`. Build and the live steps use `bq`/`gcloud`.

### Decisions (user answers, 2026-11-07, through in-thread forms)

| # | Decision | Answer |
|---|---|---|
| U1 | Window | **Today, finished before 07:00 ICT Sunday 2026-11-08** (target: writers resumed by 06:30) |
| U2 | Dataform | **The agent edits through the Dataform API:** workspace, then edit, compile, commit, push, and verify the release config compiles |
| U3 | Old-table fence | **New least-privilege runtime service account.** Every ingestion service moves to it; it can write only `raw` |
| U4 | Three services with no repo source (`pancake-orders-returned`, `jushuitan-inventory`, `meta-raw-ads-reporting-my`) | **Recover the deployed source, add it to the repo, repoint to `raw`, test, deploy** |
| U5 | `dianplus-inventory` defect | **Fix it** (page size within the API limit; an API error returns non-success), **then backfill** the missed 2026-11-06 window into `raw` after cutover |
| U6 | Git | **Commit on the current branch `main` and push** once production checks pass |
| U7 | Old tables | **Keep them until the user approves retirement.** Nothing is dropped; remind after about 14 clean days |
| U8 | Orbyn work mode | **simple** (edit in this checkout). `harness.py setup` could not save it ("no workspace found"), so it applies to this task only |

The user's request authorizes the live actions in Phase 5, each named there: create the SA and grants, run the
rehearsal, pause and resume schedulers, copy the tables, deploy the services, deploy SQL, edit Dataform, redeploy and run the dbt job,
and run one backfill. Each step still runs only after its preconditions pass. Anything outside that list, or a failed
gate, stops and is asked about through a form. Deleting old tables, rotating credentials (vendor consoles) and
deleting old images are **out of scope**.

### Fence design (U3)

New SA `lsoul-ingest-runner@marine-cycle-484213-b4.iam.gserviceaccount.com`:
- project `roles/bigquery.jobUser` (run load jobs)
- `roles/bigquery.dataEditor` on dataset `raw` only, granted in the dataset ACL
- `roles/secretmanager.secretAccessor` on each of the 11 secrets the services use (`pancake_pos` plus the ten from 2026-11-06),
  plus any secret created for a recovered service
- no project Editor and no access to the old datasets

Every ingestion service is deployed with `--service-account` set to the new SA. A stray write to an old table then fails
with 403 instead of silently splitting data. The compute default SA keeps Editor (removing it is a follow-up; other
workloads may use it). Readers of `raw`: `dbt-runner@` (`dataViewer`), the Dataform service agent (`dataViewer`), and
the principals W1 finds reading old raw tables (from `JOBS_BY_PROJECT.referenced_tables`, 30 days). Check what the
Meta `create_dataset_if_not_exists` path needs (only `datasets.get` when `raw` exists).

### Reader inventory (closes plan risk "consumers outside the repos")

Before freezing, list every principal or job that read an old raw table in the last 30 days
(`referenced_tables` by `user_email`), plus views (`INFORMATION_SCHEMA.VIEWS` in every dataset) and routines
(`INFORMATION_SCHEMA.ROUTINES`) whose definitions name an old raw table, and BigQuery scheduled queries
(Data Transfer configs). Each one is repointed in Phase 5 or listed as an owner action (for example Looker
Studio data sources, which only the owner can edit). The old tables stay frozen, so an unrepointed reader sees
stale data, not an error. The handoff names every such reader.

### Rollback

Use the plan's reverse reconciliation. Per service: `gcloud run services update-traffic <svc> --to-revisions <prev>=100`.
The previous revisions run as the compute SA and write the old datasets, so do the reverse copy first. SQL: redeploy
the baseline definitions saved in B3. Dataform: revert the workspace commit and push. dbt: redeploy the previous job
image. Rollback is possible until credentials are rotated (out of scope).

### Risks added on 2026-11-07

| Risk | Impact | Mitigation |
|---|---|---|
| A recovered service's source holds baked credentials | High (a secret ends up in Git) | Scan before adding; move each value to Secret Manager through the BB secrets form; `validate_repo.py` credential scan; never print the values |
| The source can't be recovered for one of the 3 services | Med | Fallback for that service, asked through a form: env-var repoint if its code reads one, otherwise rebuild it from the closest repo service (`local_run/pancake_orders_returned.py` exists) |
| The new SA is missing a permission the code needs | High (loads fail at 07:00) | Rehearse with the new SA in B2. The C6 backfill is a live write through the new SA before the schedulers resume |
| 26 source deploys take too long for the window | Med | About 5 min each. Run 3–4 at a time; start by 16:00. Gate: writers must resume by 06:30, otherwise roll back the readers and resume on the old datasets |
| A Dataform repo not on the plan's list reads old raw tables | High (stale core and reportdb) | A6 scans all 11 repositories' files, not only the names on the list |
| The dbt job image or ref can't be updated cleanly | Med | B4 finds how `dbt-daily-build-trigger` gets code before freezing; if unclear, ask through a form |
| 44 unrelated unit-test failures hide a new regression | Med | Compare failing test IDs before and after; any new failure blocks |
| A source of the 4 no-load services is really broken (not empty) | Low | Report it; it doesn't block the cutover |
