---
name: add-ingestion-pipeline
description: Add a new API source or endpoint to the LSOUL BigQuery ingestion code, or change what an existing pipeline fetches (fields, endpoint, date window). Covers copying the closest Cloud Run service, credentials via environment variables, the raw table schema script, staging/core SQL, the pipeline inventory and offline validation. Use for any new or modified extraction in src/.
---

# Add or update an API ingestion pipeline

## Purpose

Create or modify a pipeline that fetches data from a source API and appends it to a BigQuery raw
table, following the repo's existing pattern so it can be deployed like the other Cloud Run services.

## Prerequisites

- Read [AGENTS.md](../../../AGENTS.md) and [docs/pipelines.md](../../../docs/pipelines.md).
- API documentation for the endpoint (pagination, auth, date filters, rate limits).
- Python environment from [docs/setup.md](../../../docs/setup.md) for import checks.
- **User authorization** before any step that calls the API, creates tables, or deploys.

## Relevant files

- Template candidates in `src/cloud_run/`: `cloud-run-pancake-order/` (API key + page/page_size),
  `cloud-run-dianplus-order/` (signed requests, token cache, date chunking),
  `cloud-run-tiktok-gmv-max-report/` (Access-Token header, 30-day chunks),
  `cloud-run-meta-ads-reporting-a/` (Graph API paging, date presets).
- Each service folder: `Dockerfile` (identical everywhere), `requirements.txt` (identical except
  surfosm-inventory), `app_runner.py` (loads `cr-*.py` by file name), `cr-<source>-<entity>.py`.
- `src/local_run/`, `src/csv_export/`: optional local/CSV variants.
- `src/schema/bq-raw_<source>..<table>.py`: raw table DDL (destructive; see the schema skill).
- `sql/staging/`, `sql/core/`, `sql/procedures/`: downstream SQL.
- `.env.example`, `docs/pipelines.md`, `scripts/validate_repo.py` (`CREDENTIAL_ENV_VARS`).

## Steps

1. **Choose names.** Service folder `cloud-run-<source>-<entity>` (hyphens), script
   `cr-<source>-<entity>.py`, destination `<dataset>.raw_<entity>` following the source's existing
   dataset convention (see [sql/README.md](../../../sql/README.md#data-flow)). Confirm with the user.
2. **Copy the template folder** (all four files) and rename the script. Update `app_runner.py`'s
   `with_name("…")` and module name to the new script file name. Don't edit other services.
3. **Adapt the script:**
   - Credentials: `os.environ["<SOURCE>_<NAME>"]`, with `load_dotenv()` called after the imports.
     Add the name to `.env.example` and to `CREDENTIAL_ENV_VARS` in `scripts/validate_repo.py`.
   - `load_data()`: endpoint, pagination, date params; keep times in `Asia/Ho_Chi_Minh` unless
     the API requires otherwise (convert explicitly, as Dianplus does for Shanghai).
   - `COLUMN_RENAME_MAP`: map flattened JSON paths to snake_case column names; it defines the raw schema.
   - `insert_to_bigquery()`: keep `WRITE_APPEND`, `ALLOW_FIELD_ADDITION`/`RELAXATION`, STRING casting.
   - `run_export()`: define the default window, and **return a `(message, status)` tuple on every path**,
     including "no data" (many existing scripts return `None` there, which makes Flask respond 500).
   - Keep `--dry-run`, `--start-date`, `--end-date`, `--project-id` flags consistent with siblings.
4. **Schema script** (optional but recommended): copy a `src/schema/` script, set dataset/table and
   fields matching the rename map. Don't run it (it drops existing tables).
5. **SQL** (if the data feeds reporting): `sql/staging/stg_<source>_<entity>.sql`, a core build
   script, and `sql/procedures/sp_<source>_core_<entity>_insert.sql` modeled on an existing one.
6. **Inventory:** add a row to `docs/pipelines.md` (service, endpoint, default window, flags,
   destination, load, schedule "unknown" until confirmed).
7. **Validate offline** (skill `validate-changes`):
   ```bash
   python3 scripts/validate_repo.py
   python3 -m unittest discover -s tests
   .venv/bin/python scripts/validate_repo.py --imports
   ```
   Expected: all `PASS`; the new service appears in the import check without errors.
8. **Hand back** with a list of what still needs authorization: first API call (`--dry-run`),
   creating the raw table, the first real load, Cloud Run deploy with secrets, and a scheduler entry.

## Expected result

A self-contained new folder under `src/cloud_run/`, updated `.env.example`, `docs/pipelines.md`
and (optionally) schema/SQL files; offline checks pass; nothing has touched external systems.

## Operational limits

- Don't call the API, create tables, deploy, or add scheduler jobs without explicit authorization.
- Don't import code from other service folders or the repo root; each folder is a Docker build context.
- Changing an existing pipeline's destination, columns, date window or write disposition changes a
  production interface: list the downstream SQL that reads the table (`git grep <table> sql/`) and
  get agreement first.
- If the change should also apply to `local_run/` or `csv_export/` variants, update them or say you didn't.

## Proposed (not implemented)

- A shared ingestion library and a generator for new services.
- Automated deployment and scheduling definitions in the repo.
