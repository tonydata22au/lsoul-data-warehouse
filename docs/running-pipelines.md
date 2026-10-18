# Running pipelines

> **Every command on this page calls a production source API, and most write to production
> BigQuery.** Don't run anything here without explicit authorization for that specific
> run (which pipeline, which date range, which destination). There is no sandbox project,
> mock mode, or offline dry run in this repository.

Look up the exact flags, default window and destination in [pipelines.md](pipelines.md) first.

## Before any run

1. Setup done ([setup.md](setup.md)): virtualenv, `.env` with the needed credentials, and
   `GOOGLE_APPLICATION_CREDENTIALS` for local BigQuery access.
2. Know the side effects:
   - Loads are **append-only** (`WRITE_APPEND`). Re-running a date range adds duplicate rows to
     raw tables; core procedures deduplicate only for the current day's partition.
   - Full-snapshot pipelines (e.g. `dianplus-product`, `pancake-variations`, `tiktok-ads`) append
     the whole catalogue every run.
3. Prefer the smallest window that answers the question (`--start-date … --end-date …`, or
   `--max-pages 1` on Pancake Cloud Run scripts).

## Cloud Run script, run locally

```bash
set -a; source .env; set +a            # or rely on load_dotenv() in the script
cd src/cloud_run/cloud-run-pancake-order
../../../.venv/bin/python cr-pancake-order.py --start-date 2026-10-01T00:00:00 --end-date 2026-10-01T23:59:59 --dry-run
```

- `--dry-run` / `--dry_run` (where it exists) fetches from the API and prints the DataFrame head
  but skips the BigQuery load. It **does call the API**.
- Without `--dry-run`, the script appends to the destination table using your local Google
  credentials (Application Default Credentials: `gcloud auth application-default login`, or
  `GOOGLE_APPLICATION_CREDENTIALS`).
- `cr-magento-order.py` has no CLI; running it starts a Flask server.

## Local runner

```bash
set -a; source .env; set +a
.venv/bin/python src/local_run/pancake_order.py --start-date 2026-10-01T00:00:00 --end-date 2026-10-01T23:59:59
```

No `local_run/` script has a dry-run flag. TikTok scripts and `pancake_orders_returned.py` support
`--list`, which fetches, prints the columns and exits before loading. Jushuitan and Magento local
scripts prompt for dates with `input()`; don't run them non-interactively.

## Deployed Cloud Run service

A request to the service root triggers a full export with the default window:

```bash
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" https://<service-url>/
```

Service URLs, regions and schedules are **not recorded in this repo**. Find them in the Cloud Run
console (project `marine-cycle-484213-b4`, region `asia-southeast1` per the docstrings).

## Deploying (not managed by this repo)

There is no deploy script or CI. Some scripts' docstrings contain `gcloud run deploy` examples,
but their `--source` paths point to folders outside this repo, and the one in
`cloud-run-tiktok-thai-gmv-max-report` deploys under the **VN** service name. Treat them as
unverified. A deploy from this repo would look like the following (unverified; confirm the service
name, account, and env vars first):

```bash
gcloud run deploy <service-name> --source src/cloud_run/<service-folder> \
  --project marine-cycle-484213-b4 --region asia-southeast1 --no-allow-unauthenticated \
  --set-secrets PANCAKE_API_KEY=<secret-name>:latest   # one per credential the service reads
```

Since 2026-10-18, services read credentials from environment variables; a deploy without them
fails (see [restructure-2026-10.md](restructure-2026-10.md#deployment-impact)).

## Checking a load (read-only SQL, still needs authorization to query production)

```sql
SELECT DATE(_PARTITIONTIME) AS load_day, COUNT(*) AS row_count
FROM `marine-cycle-484213-b4.raw_pancake.raw_order`
WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)
GROUP BY load_day ORDER BY load_day;
```

`sql/ad_hoc/q-check_scheduler_status.sql` checks freshness across the `raw_pancake` tables.
