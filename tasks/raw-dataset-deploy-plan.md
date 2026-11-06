# Deploy plan: Cloud Run code fixes tonight, on the current datasets (2026-11-06, ICT)

Request: "Approve and deploy this tonight, always ask me questions in /in-thread-forms". Questions go through
in-thread forms (Claude Code's native question tool). The task list lives here because `tasks/todo.md` holds
other, still-open work. Background: [raw-dataset-local-verification.md](raw-dataset-local-verification.md),
[../docs/raw-destination-contract.md](../docs/raw-destination-contract.md).

## Decisions (answered in forms, 2026-11-06 ~18:30 ICT)

| # | Question | Answer |
|---|---|---|
| D1 | Scope tonight | **Code fixes only, current datasets.** No `raw` dataset, data copy, SQL, Dataform or dbt change |
| D2 | Surfosm orders/returns | **Fail the run on any failed detail** (code change tonight) |
| D3 | Empty-day 500 → 200 (10 services) | **Approved** |
| D4 | Secret rotation | **Deploy first, then the user rotates** `DIANPLUS_APP_SECRET` / `JUSHUITAN_APP_SECRET` |
| D5 | `cloud-run-pancake-order_returned` | **Leave out** of tonight's deploy (live revision untouched) |
| D6 | 44 warehouse-name test failures | **Waived** for this deploy (not caused by this change) |
| D7 | Dianplus `resultCode` / Jushuitan `code` non-success | **Revert to the old behaviour**: stop and load the rows fetched so far |
| D8 | Revert scope | **Only the API-code branch.** HTTP 5xx and connection failures still fail the run with no load |
| D9 | Commit | **Commit on the current branch (`main`)**, only this change's files, local only (no push) |
| D10 | Credential echo in error text | **Redact tonight**: Pancake (deployed services), Meta ×2, Dianplus auth ×4 |
| D11 | Rollout | **Canary one service, then confirm in a form**, then the rest. Only services that already exist in Cloud Run |
| D12 | Verification | **Revision checks tonight** (Ready, image, BQ_* env, startup logs). Data checks come from tomorrow's scheduled runs |
| D13 | Plan go (three bullets) | **Go** |
| D14 | Review timing | **Independent read-only review of the code diff inside Build**, after the offline checks and before the T5 gate. Agent Flow's Review stage runs after Build, and Ship may not deploy, so it reviews the deployed result afterwards |

## Objective and success criteria

Ship the local fixes to the existing Cloud Run services tonight **without changing any BigQuery destination**:
each service keeps writing its current dataset through `BQ_RAW_DATASET` / `BQ_DATASET` overrides.

Done means:
- Every deployed service runs a new Ready revision serving 100%, from this repo's folder, committed locally.
- Its destination env var points to its current dataset (table below), and nothing else in its config changed.
- No service URL was called, and no scheduler, IAM, BigQuery, secret or Dataform change was made.
- Each service has a rollback command naming its previous revision.
- The offline suites for this change pass, and the runbook covers tomorrow's runs (2026-11-07).

## Destination overrides (must match the live inventory, otherwise stop)

| Services | Override |
|---|---|
| Pancake ×11: customer, ecom-product, inventory_histories, order, product, product_variations, stats_inventory_product, stats_inventory_variations, stats_order, stats_product, variations, warehouse_transfer (whichever exist live) | `BQ_RAW_DATASET=raw_pancake` |
| TikTok ×6 (VN + TH) | `BQ_RAW_DATASET=raw_tiktok` |
| Meta ×2 | `BQ_RAW_DATASET=raw_meta` (an existing dataset, so `create_dataset_if_not_exists` creates nothing) |
| Dianplus ×4 | `BQ_RAW_DATASET=dianplus` |
| jushuitan-order | `BQ_RAW_DATASET=jushuitan` |
| surfosm-order, surfosm-order_return | `BQ_RAW_DATASET=surfosm` |
| magento-order | `BQ_DATASET=magento` (BQ_PROJECT/BQ_TABLE defaults unchanged) |
| surfosm-inventory | `BQ_DATASET=surfosm` |
| pancake-order_returned | **not deployed** (D5) |

The committed code defaults to `raw`, which doesn't exist yet. A missing override would make loads fail, and
the Meta services would create `raw` themselves. So every deployed revision's env is checked before moving on.

## Tasks

### Phase 1: code (offline, TDD)

- [ ] **T1 Surfosm fail-on-failed-detail (D2).** In `fetch_order_details()` of cloud-run-surfosm-order and
  cloud-run-surfosm-order_return, a failed request, a parse error or `ok: false` raises before any load (the
  single load comes after fetching, so a retry is safe).
  - Acceptance: the two `READINESS_BLOCKERS` tests pass as normal tests, the map is empty, and the parity test
    still passes.
  - Verify: `test_cloud_run_fetch` on 3.11 and 3.13. Files: 2 services, `tests/test_cloud_run_fetch.py`.
- [ ] **T2 API-code revert (D7, D8).**
  - Dianplus ×4: `resultCode != "success"` goes back to `break`.
  - Jushuitan: `code != 0` stops and returns rows so far. Pages that fail after retries still raise.
  - Acceptance: `page2_api_error` for these 5 services expects 2xx plus a load of the page-1 rows (owner-approved,
    documented in the contract). `page2_http_500` and connection resets still fail with no load.
  - Verify: fetch tests. Files: 5 services, the fetch test, contract.
- [ ] **T3 Redact credentials in error text (D10).**
  - Port pancake-order's `redact_api_key` (masks `api_key`/`access_token`, `raise … from None`) to the deployed
    Pancake services and Meta ×2, and redact `appSecret` in the Dianplus auth errors.
  - Make the harness realistic first: fake response URLs carry the query string, and connection errors include
    the request path and query, as urllib3 does.
  - Acceptance: no credential value appears in any route or CLI failure output, which the new test checks for
    every service.
  - Verify: RED before, GREEN after, on 3.11 and 3.13. Files: about 17 services plus the harness and route tests,
    split into slices of 5 or fewer.
- [ ] **Checkpoint 1.** On 3.11 and 3.13:
  - change-scoped suites pass; `validate_repo` 0; `check_service_imports` 30/30; manifest regenerated, `--check` 0;
    `sql_index --check` 0
  - mutation spot-check of T1–T3 (one reintroduced defect each is caught)
  - contract, runbook and verification record updated for D2, D7 and D10

- [ ] **R1 Independent pre-deploy review (D14).** A separate agent reviews the Phase 1 diff read-only (services
  and tests), with severity labels. Serious findings are fixed and re-checked before T4. Unclear findings are
  asked in a form.

### Phase 2: commit (local)

- [ ] **T4 Commit on `main` (D9).** Commit only this change's files:
  - `src/cloud_run/**` (excluding nothing; `pancake-order_returned` changes are committed but not deployed)
  - `tests/cloud_run_harness*.py`, `tests/test_cloud_run_*.py`, `tests/test_validate_repo.py`,
    `scripts/validate_repo.py`
  - `docs/raw-destination-contract.md`, `docs/raw-dataset-next-run-monitoring.md`, `tasks/raw-dataset-*.md`

  Other raw-dataset files (SQL, `local_run/`, `schema/`, manifest, shared docs) and every other session's file
  stay uncommitted. The commit message lists the scope. No push.
  - Acceptance: `git show --stat HEAD` lists only those paths, and their working-tree copies are clean.
  - Verify: `git status --porcelain -- <paths>` is empty.

### Phase 3: live, behind form gates (each gate is a form; stop on any mismatch)

- [ ] **T5 Read-only inventory.**
  - `gcloud` account and project; `gcloud run services list` across regions; the folder → service map.
  - Per service: region, serving revision (the **rollback target**), image, service account, ingress and auth
    setting, and only the destination variables (`BQ_RAW_DATASET`, `BQ_DATASET`, `BQ_TABLE`, `BQ_PROJECT`,
    `GCP_PROJECT`) through a `jq` allowlist.
  - Credential env var **names only**, to confirm `TIKTOK_TH_ACCESS_TOKEN` is present.
  - `gcloud scheduler jobs list` (schedule, target, `httpMethod`).

  The output is saved in thread storage, never in the repo, and no values outside the allowlist are printed.
  - Acceptance: every deploy candidate maps to exactly one live service, and its current destination matches
    the override table.
  - Gate: a form shows the deploy list, the overrides, the canary and anything unexpected (a service missing live,
    a destination mismatch, a POST scheduler on a GET-only route, a code-only table), and asks to proceed.
- [ ] **T6 Canary.** Deploy one low-risk existing service:
  `gcloud run deploy <svc> --source src/cloud_run/<folder> --region <r> --project marine-cycle-484213-b4 --update-env-vars <override> --quiet`.
  No traffic, auth, scaling or service-account flags.
  - Acceptance: a new revision is Ready and serves 100%, the image changed, the destination env equals the
    override, every other env name is unchanged, and the startup logs have no errors. No request is sent.
  - Gate: a form with the canary result asks to deploy the rest.
- [ ] **T7 Deploy the rest** (D5: not `pancake-order_returned`), sequentially or in small groups, with the same
  command and checks per service. Record the new revision names.
  - On any failure: roll that service back (below), stop, and ask in a form.
- [ ] **T8 Close out.**
  - A per-service table of old revision → new revision, override, status.
  - Update the runbook for **scenario C** (fixed code on old datasets) for the 2026-11-07 runs.
  - Tell the user to rotate the two secrets now (D4) and how that interacts with revisions (they update the
    secret themselves).
  - Leave the kanban card in review.

## Rollback

Per service, instantly: `gcloud run services update-traffic <svc> --region <r> --to-revisions <previous-revision>=100`,
with the previous revision recorded in T5. Code rollback: the T4 commit can be reverted locally.

Nothing in BigQuery, the schedulers, IAM or Dataform changes tonight, so there is no data rollback. Rotated
secrets aren't rolled back.

## Boundaries

- **Never:**
  - call a service URL or trigger a scheduler job
  - pause or resume a scheduler, or change IAM
  - create, copy or alter any BigQuery dataset or table
  - touch Dataform or dbt runs
  - read or print secret values, `.env` or `credentials/`
  - push, or create a new Cloud Run service
- **Ask in a form first:** every live gate (T5, T6, T7), any deviation from this plan, and any deploy-list change.

## Risks

| Risk | Mitigation |
|---|---|
| The live image differs from this repo's folder (deploy commands pointed at Drive folders) | Canary first; previous revision recorded; instant traffic rollback |
| A missed destination override sends loads to the non-existent `raw` (Meta would create it) | Per-revision env check before moving on; the overrides come from the T5 inventory |
| A service exists live but its table doesn't (7 code-only tables) | Listed at the T5 gate for an explicit decision |
| The Thai ads service starts for the first time and writes `raw_tiktok_thai_ads` | `TIKTOK_TH_ACCESS_TOKEN` checked by name at T5; it is a live table already |
| D7 keeps silent partial loads on API error codes for Dianplus/Jushuitan | Documented in the contract and the runbook's fetch-error search |
| Running out of time before 07:00 ICT (first runs about 07:20) | Phase 3 stops cleanly after any service; deployed services are independent |
