# AGENTS.md: LSOUL data warehouse

This is the canonical guide for AI coding agents (Codex, Claude Code, and others) and a
quick orientation for engineers. Keep it short; details live in `docs/` and in the skills.

## What this repository does

LSOUL is a fashion brand. This repo pulls data from its operational and marketing systems
(Pancake POS, Dianplus, Jushuitan, Magento, Surfosm/ScaleUp fulfilment, TikTok Ads, Meta Ads)
through their HTTP APIs with Python, appends it to raw tables in **Google BigQuery**
(project `marine-cycle-484213-b4`, location `asia-southeast1`), and transforms it with
BigQuery SQL (staging → core → reporting functions → dashboards). Notebooks analyze the
results.

There is no shared Python package, no orchestrator, and no CI in this repo. Each pipeline
is a self-contained script. Scheduling and deployment are configured outside the repo
(Cloud Run + an external trigger; see [docs/pipelines.md](docs/pipelines.md)).

## Reading path

1. This file: map, commands, boundaries.
2. [docs/architecture.md](docs/architecture.md): how data flows and why the code looks the way it does.
3. [docs/pipelines.md](docs/pipelines.md): every entry point → source → BigQuery table → load strategy → schedule.
4. [sql/README.md](sql/README.md): warehouse layers, datasets and load semantics.
5. The skill that matches your task (see [Skills](#skills)).
6. [docs/setup.md](docs/setup.md), [docs/running-pipelines.md](docs/running-pipelines.md), [docs/troubleshooting.md](docs/troubleshooting.md) as needed.

## Repository map

```text
src/                     Python ingestion (one self-contained script per pipeline)
  cloud_run/<service>/   Deployed Cloud Run services. Each folder is its own Docker build context:
                         Dockerfile + requirements.txt + app_runner.py (gunicorn entry) + cr-*.py (logic)
  local_run/             Local CLI variants of the pipelines (load to BigQuery from a laptop)
  csv_export/            Manual exporters that write CSV files (no BigQuery writes)
  schema/                One-off scripts that DROP and recreate raw BigQuery tables (schema + partitioning)
sql/                     All BigQuery SQL: staging/, core/, procedures/, functions/, ad_hoc/, working_files/, archive/
notebooks/               Analysis notebooks (outputs are stripped from Git by a clean filter)
scripts/                 Repo tooling: validate_repo.py (offline checks), nbstrip.py (notebook filter)
tests/                   unittest suite for the tooling and repository invariants (offline)
docs/                    Architecture, pipeline inventory, setup, running, troubleshooting, migration notes
.agents/skills/          Canonical agent skills (Codex reads these natively)
.claude/                 Claude Code adapters: skills/ symlinks to .agents/skills/, settings.json guardrails
seeds/, data/            Local input/output files. Gitignored; may contain business data
credentials/, .env       Local secrets. Gitignored. Never read, print, or commit them
```

## Commands

Safe commands make no network calls and write nothing outside the working tree:

| Purpose | Command | Side effects |
|---|---|---|
| Offline repo checks | `python3 scripts/validate_repo.py` | None |
| Checks + import every Cloud Run service | `.venv/bin/python scripts/validate_repo.py --imports` | None. Isolated subprocesses: dotenv disabled, dummy credentials, temp HOME, sockets blocked |
| Unit tests | `python3 -m unittest discover -s tests` | None |
| Syntax-check one file | `python3 -m py_compile <file>` | Writes `__pycache__` only |
| Show a pipeline's CLI flags | Read its `argparse` block, or see [docs/pipelines.md](docs/pipelines.md) | None. Avoid `--help`: it imports the module, which loads `.env`, may read the service-account key, and in some scripts (e.g. the Meta CSV exporter) runs the export at import |

These commands **reach external systems**. Run them only when the user explicitly asks,
and say what they will touch first:

| Action | Command pattern | Effect |
|---|---|---|
| Run any pipeline script | `python src/cloud_run/<svc>/cr-*.py …`, `python src/local_run/*.py …` | Calls the source API; **appends rows to BigQuery** (`cr-magento-order.py` starts a Flask server instead) |
| "Dry run" a pipeline | `--dry-run` / `--dry_run` (most Cloud Run scripts), `--list` (some local scripts) | **Still calls the source API**; skips only the BigQuery load. `local_run/` has no dry-run flag |
| CSV exporters | `python src/csv_export/…` | Calls the source API; writes CSVs to hardcoded Google Drive paths. No BigQuery writes |
| Schema scripts | `python src/schema/…` | **Deletes and recreates the raw table if it exists (data loss)**; `--csv` then loads with `WRITE_TRUNCATE` |
| Any SQL file in `sql/` | BigQuery console / `bq query` | DDL/DML: rebuilds tables, replaces procedures/functions |
| Deploy | `gcloud run deploy …`, `docker push …` | Changes production services |
| Hit a service URL | `curl https://<service>/` | Triggers a production ingestion run |

There is no offline or mock mode for pipelines. Don't invent a dry-run flag.

## Conventions

- **Credentials** come from environment variables only: `os.environ["PANCAKE_API_KEY"]` etc.
  Scripts call `load_dotenv()` so local runs read the repo-root `.env`; Cloud Run services get
  real env vars. The full list is in [.env.example](.env.example). Never hardcode a credential;
  `validate_repo.py` catches the common patterns, but review diffs too.
- **Pipeline shape** (most scripts): `load_data()` (paginated API fetch) → `flatten_data()`
  (`json_normalize`) → `rename_and_reorder_columns()` (via a `COLUMN_RENAME_MAP`) → type/clean helpers →
  `insert_to_bigquery()` (`load_table_from_dataframe`, usually `WRITE_APPEND`, all columns cast
  to STRING) → `run_export()` shared by the CLI `main()` and the Flask `/` route.
- **Times**: inputs and default windows use Vietnam time (`Asia/Ho_Chi_Minh`).
- **Duplication is intentional for now**: each Cloud Run folder must stay self-contained because
  its Dockerfile copies only that folder. Don't import across service folders. If logic changes,
  update the matching `local_run/` and `csv_export/` variants or note that you didn't.
- **Don't rename or move `src/cloud_run/*` folders or `cr-*.py` files**: external deploy
  commands and `app_runner.py` depend on those paths (including the `autction` typo).
- **SQL**: one object per file, fully qualified `` `marine-cycle-484213-b4.<dataset>.<object>` ``.
  Superseded files go to `sql/archive/` with the `zarchived-` prefix. See [sql/README.md](sql/README.md).
- Keep diffs small. Match the surrounding style. Don't reformat files you aren't changing.

## Making and validating a change

1. Find the pipeline in [docs/pipelines.md](docs/pipelines.md); read the script end to end.
2. Make the change in every variant that should change (cloud_run / local_run / csv_export).
3. If columns or tables change, update the schema script and downstream SQL (skill: `bigquery-schema-and-loads`).
4. Run `python3 scripts/validate_repo.py` and `python3 -m unittest discover -s tests`;
   with pipeline dependencies installed, add `--imports`.
5. Update docs/pipelines.md when an entry point, destination, schedule or env var changes.
6. Review `git diff` for secrets, real data and unintended edits before committing.

## Boundaries

- Don't run ingestion, backfills, CSV exports, schema scripts, SQL, deployments, or service
  URLs without explicit user authorization for that specific action.
- Never read, print, log, or commit `.env`, `credentials/`, tokens, or customer data. Don't
  paste query results with personal data into docs or commits.
- Don't change BigQuery destinations, write dispositions, column names or date windows unless asked.
  These are pipeline interfaces that downstream SQL depends on.
- Don't delete files because they look unused. Archive SQL instead; ask before removing code.
- Don't push, open pull requests, or rewrite Git history unless asked.

## Skills

Canonical skills live in [.agents/skills/](.agents/skills/). Claude Code sees the same files
through symlinks in `.claude/skills/`.

| Skill | Use it to |
|---|---|
| [add-ingestion-pipeline](.agents/skills/add-ingestion-pipeline/SKILL.md) | Add a new API source/endpoint or change what an existing pipeline fetches |
| [run-pipeline](.agents/skills/run-pipeline/SKILL.md) | Run a pipeline (with authorization) and troubleshoot failures |
| [bigquery-schema-and-loads](.agents/skills/bigquery-schema-and-loads/SKILL.md) | Change raw table schemas, load behavior, staging/core SQL |
| [validate-changes](.agents/skills/validate-changes/SKILL.md) | Check any change before handing it back |

## Known issues

See [docs/troubleshooting.md](docs/troubleshooting.md#known-issues). The ones most likely to
surprise you:

- `cloud-run-tiktok-thai-ads` can't start: its `app_runner.py` loads a file that doesn't exist.
- `cloud-run-pancake-order_returned` is a copy of `cloud-run-pancake-order` and also appends to `raw_pancake.raw_order`.
- `local_run/` and `schema/` default to `src/credentials/google-credentials.json`, not the repo-root
  `credentials/` folder, so set `GOOGLE_APPLICATION_CREDENTIALS`.
- Deploy commands in script docstrings point to folders outside this repo, and one targets the wrong
  service name. Don't copy them.
