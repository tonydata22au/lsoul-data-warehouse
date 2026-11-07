# Plan: raw-dataset cutover follow-ups (2026-11-07)

Continues @thread:thr_ssazbmz9k4 (cutover live; record in
[raw-dataset-local-verification.md](raw-dataset-local-verification.md#cutover-2026-11-07)). The owner chose all four
follow-ups in this thread. Separate from `tasks/plan.md` / `tasks/todo.md` (other work).

## Spec

- **Objective:** remove the known post-cutover breakages left in the repos and confirm the first scheduled run on `raw`.
- **Boundaries.** Always: offline checks before handing back; read-only BigQuery only. Ask first: deploying SQL,
  `cloudrun.sh apply`, `git push`, dropping live routines. Never: run pipelines, write BigQuery, read `.env`/`credentials/`.
- **Commands:** `python3 scripts/validate_repo.py`, `python3 scripts/sql_index.py --check`,
  `python3 -m unittest discover -s tests` (warehouse); `bash -n deploy/cloudrun.sh`, `deploy/cloudrun.sh plan`,
  `uv run python -m unittest discover -s scripts -p 'test_*.py'` (lsoul_dbt).

## Tasks

- [x] **T1 dbt deploy script** (`lsoul_dbt/deploy/cloudrun.sh`, 1 file, XS). `apply` must not stop at deleted datasets
  (`core_meta`, `core_tiktok`). Acceptance: a `Not found` from `bq show` skips the grant; any other `bq` error still fails;
  `plan` output unchanged. Verify: stub-`bq` harness (gone/ok/denied), `bash -n`, `plan`, unit tests (no new failures).
  Done: local commits `c0b393f` (fix) and `c519487` (`GrantDatasetTest`: fails on the old script, passes now), not pushed.
- [x] **T2 `reportdb.fn_warehouse_operations`** (function + 3 generated `sql/monitoring/looker_studio_*`, S). Acceptance:
  no scan of a deleted dataset (`core_meta`, `core_tiktok`, `dataform`, `stg_meta`, `stg_tiktok`); dbt layer datasets
  `core`, `stage`, `mart` scanned and labelled by source. Verify: `validate_repo.py`, `sql_index.py --check`, unit tests;
  BigQuery dry run of the DDL (passed 2026-11-07).
- [x] **T3 `jushuitan.sp_jushuitan_core_inventory_insert`** (1 file, XS). Superseded by dbt
  `core.core_jushuitan__inventory`; its source is gone and nothing reads its output. Acceptance: file archived as
  `sql/archive/zarchived-…`; live procedure untouched. Verify: `validate_repo.py` (`check_sql_layout`).
- [x] **T4 read-only health check** (no files). Acceptance: raw tables, readers and today's loads queried read-only.
  Done 2026-11-07 ~16:40 ICT (auth renewed): all 32 `raw` tables present (last modified at the 14:41–14:43 copy;
  `raw_dianplus_inventory` 15:08 backfill); migration query 1c = 0 rows (old tables frozen); today's LOAD jobs into old
  datasets all ran 07:00–07:16 ICT, before the cutover; the only LOAD into `raw` is the backfill as `lsoul-ingest-runner@`;
  after 16:00 the only old-raw references are this check's own queries (`ops.data@`). Same-day empty partitions
  (`raw_product_variations`, `raw_dianplus_order_refund`, TikTok/Meta dimension tables) match the known empty days.
- [ ] **T5 Sunday monitor** (2026-11-08 08:47 ICT, session-only cron `aa28d5df`). Acceptance: scenario D of
  [the runbook](../docs/raw-dataset-next-run-monitoring.md) PASS/FAIL per check with evidence. Runs only while this session is open.

### Checkpoint

- [x] Warehouse: validate_repo PASS, sql_index 0 problems, unittest 44 failures = same 44 as `HEAD` (no new ones).
- [x] lsoul_dbt: 152/153 pass; the 1 failure (`--schedule=0 9` expected) predates T1 (`67e1539`).

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| T2 deploy changes a live TVF used by Looker | Low | Dry run passed; roll back by redeploying the live definition saved first (`bq show --routine`) |
| Session-only cron dies with the session | Med | Re-run scenario D by hand Sunday after 08:30 |
| `grep 'Not found'` depends on bq's message text | Low | Unknown errors still fail closed |

## Open questions (owner)

1. dbt schedule: keep `0 8` (update test + comment) or restore `0 9`?
2. Deploy T2 to BigQuery? Drop the live T3 procedure?
3. Push both repos (warehouse commit, lsoul_dbt `c0b393f` + `c519487`)?
