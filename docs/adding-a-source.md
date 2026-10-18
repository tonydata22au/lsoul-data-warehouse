# Adding a new source or endpoint

The step-by-step procedure, with commands and checks, is the agent skill
[`add-ingestion-pipeline`](../.agents/skills/add-ingestion-pipeline/SKILL.md). It's written for
both people and agents. This page is the summary.

1. **Pick a template.** Copy the closest existing Cloud Run folder (same API style: paginated
   GET with API key → Pancake; signed requests → Dianplus/Jushuitan; bearer token → TikTok/Meta).
2. **Keep the shape.** `load_data` → `flatten_data` → `rename_and_reorder_columns` → clean helpers →
   `insert_to_bigquery` (`WRITE_APPEND`, STRING columns) → `run_export` used by both CLI and Flask.
3. **Credentials** via `os.environ["<SOURCE>_<NAME>"]` + `load_dotenv()`; add the name to
   `.env.example`. Never hardcode.
4. **Raw table:** create it with a schema script modeled on `src/schema/` (DAY partitioning on
   ingestion time). Creating a table is a BigQuery write; get authorization.
5. **SQL:** add `sql/staging/stg_<source>_<entity>.sql`, a core build script and an
   `sp_<source>_core_<entity>_insert.sql` procedure if the data feeds reporting.
6. **Document:** add the pipeline to [pipelines.md](pipelines.md) (the validator enforces it).
7. **Validate offline:** `python3 scripts/validate_repo.py`, `python3 -m unittest discover -s tests`,
   `.venv/bin/python scripts/validate_repo.py --imports`.
8. **First real run and deploy** only with authorization (see [running-pipelines.md](running-pipelines.md)).
