# src/

Python ingestion code. Every pipeline is a self-contained script; there is no shared package.
The full inventory (source, entry point, destination, load strategy, schedule) is in
[../docs/pipelines.md](../docs/pipelines.md).

| Folder | What it holds | Runs where | Writes to |
|---|---|---|---|
| [`cloud_run/`](cloud_run/) | One folder per deployed service: `Dockerfile`, `requirements.txt`, `app_runner.py` (gunicorn entry point that loads the `cr-*.py` module by file path), `cr-*.py` (pipeline logic + Flask `/` route + CLI) | Cloud Run (production); can also be run locally | BigQuery raw tables |
| [`local_run/`](local_run/) | Local CLI variants of the pipelines, sometimes with extra endpoints (e.g. TikTok campaign/ad group) | A laptop | BigQuery raw tables |
| [`csv_export/`](csv_export/) | Manual exporters that save API data as CSV (several to hardcoded Google Drive paths) | A laptop | CSV files |
| [`schema/`](schema/) | One-off scripts that **delete and recreate** a raw table (fixed schema, daily partitioning); some can then load a CSV | A laptop | BigQuery DDL; `--csv` loads with `WRITE_TRUNCATE` |

Rules of thumb:

- Don't rename or move `cloud_run/*` folders or `cr-*.py` files; deploy commands and `app_runner.py` use those paths.
- A Cloud Run folder is its own Docker build context; it can't import code from outside the folder.
- Credentials come from environment variables (see [../.env.example](../.env.example)); never hardcode them.
- Running any script here calls a source API, and most write to BigQuery. See
  [../docs/running-pipelines.md](../docs/running-pipelines.md) before running anything.
