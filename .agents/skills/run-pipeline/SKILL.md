---
name: run-pipeline
description: Run an LSOUL ingestion pipeline locally or trigger a Cloud Run service, only with explicit user authorization, and troubleshoot failures (missing env vars, credential paths, expired tokens, empty-day HTTP 500s, schema mismatches, duplicates, stale core tables). Use when asked to run, backfill, re-run or debug a pipeline or a failed load.
---

# Run and troubleshoot a pipeline

## Purpose

Execute a pipeline safely when the user has authorized it, and diagnose failures, using code reading
and read-only checks first.

## Prerequisites

- **Explicit authorization** naming the pipeline, the date range and whether loading to BigQuery is
  allowed. A "dry run" still calls the source API, so it needs authorization too.
- Setup from [docs/setup.md](../../../docs/setup.md): `.venv`, `.env` with the credentials the
  pipeline reads, `GOOGLE_APPLICATION_CREDENTIALS` (local scripts) or Application Default Credentials.

## Relevant files

- [docs/pipelines.md](../../../docs/pipelines.md): flags, default windows, destinations.
- [docs/running-pipelines.md](../../../docs/running-pipelines.md): commands per pipeline type.
- [docs/troubleshooting.md](../../../docs/troubleshooting.md): error table and known issues.
- The pipeline script itself (`run_export`, `load_data`, `insert_to_bigquery`).

## Steps

1. **Identify** the entry point and its exact flags in `docs/pipelines.md` (flag spelling varies:
   `--All`/`--all`/`--ALL`, `--dry-run`/`--dry_run`, `--start-date`/`--start_date`).
2. **State the plan to the user** before running: command, API called, date range, destination
   table, append vs truncate, expected duplicates. Wait for a go-ahead.
3. **Prefer the least side effect:** `--dry-run` / `--dry_run` (Cloud Run scripts) or `--list`
   (some local scripts) → small window / `--max-pages 1` → full run.
4. **Run** (examples; supported today):
   ```bash
   set -a; source .env; set +a
   cd src/cloud_run/<service> && ../../../.venv/bin/python cr-<name>.py --start-date <YYYY-MM-DDTHH:MM:SS> --end-date <…> --dry-run
   .venv/bin/python src/local_run/<file>.py <flags>
   ```
   Dry-run output prints sample rows that can contain customer data. Summarize counts; don't paste rows.
5. **Verify** with a read-only query when authorized (row counts per `_PARTITIONTIME` day; see
   `docs/running-pipelines.md`). Expect duplicates for overlapping windows.
6. **Report** the command, row counts and job ID from the script output, and anything unexpected.

## Troubleshooting order

1. Read the traceback; match it in `docs/troubleshooting.md`.
2. `KeyError: '<NAME>'` → credential not set (local `.env`, or Cloud Run service env/secret).
3. `FileNotFoundError …/src/credentials/…` → set `GOOGLE_APPLICATION_CREDENTIALS`.
4. 401/403 → expired token (TikTok/Meta): the user must issue a new one; never ask them to paste it in chat.
   Ask them to update `.env` or the secret themselves.
5. HTTP 500 `cannot unpack non-iterable NoneType` → empty window in one of the 11 affected services.
6. Schema errors → compare the table schema with `COLUMN_RENAME_MAP` and the `src/schema/` script.
7. Core not updated → staging partition date vs today (Vietnam time); `sysdb.data_insert_log`.
8. `cloud-run-tiktok-thai-ads` won't start → known issue (`app_runner.py` filename).

## Operational limits

- Never run without authorization, never widen the date range on your own, never run schema
  scripts (they drop tables) or `sql/` files as part of a "run".
- Never print, echo, or log credential values; don't `cat .env`.
- Backfills over long ranges append large volumes; confirm cost and duplicates with the user.
- Don't redeploy or change Cloud Run configuration to fix a failure without authorization.

## Proposed (not implemented)

- A sandbox BigQuery dataset or mock API mode for safe end-to-end tests.
- Structured run logs and alerting.
