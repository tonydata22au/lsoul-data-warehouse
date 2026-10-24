# LSOUL data warehouse

Data ingestion and BigQuery transformations for **LSOUL**, a fashion brand. Python pipelines pull
orders, products, inventory, customers and ad performance from the brand's systems (Pancake POS,
Dianplus, Jushuitan, Magento, Surfosm/ScaleUp fulfilment, TikTok Ads, Meta Ads) and append them to
Google BigQuery (`marine-cycle-484213-b4`). SQL models then build staging, core and reporting layers
for dashboards and notebooks.

> **Production warning:** pipeline scripts call live APIs and write to production BigQuery. There is
> no sandbox or offline mode. Read [docs/running-pipelines.md](docs/running-pipelines.md) before running anything.

## Start here

| If you want to… | Read |
|---|---|
| Understand the system | [docs/architecture.md](docs/architecture.md) |
| Find a pipeline (source → script → table → schedule) | [docs/pipelines.md](docs/pipelines.md) |
| Set up a machine | [docs/setup.md](docs/setup.md) |
| Run or debug a pipeline | [docs/running-pipelines.md](docs/running-pipelines.md), [docs/troubleshooting.md](docs/troubleshooting.md) |
| Deploy and schedule a Cloud Run service | [Deploy and schedule a Cloud Run service](#deploy-and-schedule-a-cloud-run-service) (below) |
| Add a source or endpoint | [docs/adding-a-source.md](docs/adding-a-source.md) |
| Work on SQL | [sql/README.md](sql/README.md) |
| Work as an AI agent | [AGENTS.md](AGENTS.md) (Claude Code: [CLAUDE.md](CLAUDE.md)) |
| See what changed in the 2026-10 restructure | [docs/restructure-2026-10.md](docs/restructure-2026-10.md) |

## Repository layout

```text
.
├── AGENTS.md / CLAUDE.md   Agent guidance (shared / Claude Code entry point)
├── .agents/skills/         Canonical agent skills; .claude/skills/ symlinks to them
├── src/
│   ├── cloud_run/          30 deployed Cloud Run services (one folder = one Docker build context)
│   ├── local_run/          Local CLI loaders
│   ├── csv_export/         Manual CSV exporters (no BigQuery writes)
│   └── schema/             Raw-table creation scripts (destructive: drop + recreate)
├── sql/                    BigQuery SQL: staging, core, procedures, functions, ad_hoc, working_files, archive
├── notebooks/              Analysis notebooks (outputs stripped in Git)
├── scripts/                validate_repo.py (offline checks), nbstrip.py (notebook Git filter)
├── tests/                  Offline unittest suite
├── docs/                   Architecture, inventory, setup, runbooks, migration notes, portfolio docs
└── seeds/, data/, credentials/, .env   Local only, gitignored
```

## Quick start (offline)

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt -r src/cloud_run/cloud-run-surfosm-inventory/requirements.txt
cp -n .env.example .env   # -n never overwrites an existing .env; fill in only what you need
git config filter.nbstrip.clean "python3 scripts/nbstrip.py"
git config filter.nbstrip.smudge cat
git config filter.nbstrip.required true

python3 scripts/validate_repo.py                     # offline checks
python3 -m unittest discover -s tests                # offline tests
.venv/bin/python -m unittest discover -s tests       # also runs the Cloud Run service unit tests
.venv/bin/python scripts/validate_repo.py --imports  # import every Cloud Run service (isolated, offline)
```

## Deploy and schedule a Cloud Run service

Worked example: `cloud-run-pancake-order`, which loads orders updated yesterday into
`raw_pancake.raw_order`. Every command below changes production; run them from the repo root.

**Before you start**

- Install the gcloud CLI and sign in (`gcloud auth login`) with an account that can deploy in
  `marine-cycle-484213-b4`. It needs Cloud Run Source Developer, Service Usage Consumer, Service Account
  User on the runtime service account, Secret Manager Admin and Cloud Scheduler Admin.
- If the upload fails with `serviceusage.services.use` denied, your gcloud quota project points at another
  project. Add `--billing-project marine-cycle-484213-b4` to each command, or run
  `gcloud config set billing/quota_project marine-cycle-484213-b4`.
- Since the 2026-10 restructure, scripts read credentials from environment variables. Images built
  earlier may have none set, so check a service before you redeploy it:
  `gcloud run services describe <service> --region asia-southeast1 --format="yaml(spec.template.spec.containers[0].env)"`.

**1. Store the API key in Secret Manager** (once; `pancake_pos` already exists). Type the key at the
prompt so it never appears in your shell history or a chat:

```zsh
read -s "PANCAKE_KEY?Pancake API key: " && echo && \
printf '%s' "$PANCAKE_KEY" | gcloud secrets create pancake_pos --data-file=- \
  --replication-policy=automatic --project marine-cycle-484213-b4; unset PANCAKE_KEY
gcloud secrets add-iam-policy-binding pancake_pos --project marine-cycle-484213-b4 \
  --member serviceAccount:266174294882-compute@developer.gserviceaccount.com \
  --role roles/secretmanager.secretAccessor
```

That `read` syntax is zsh; in bash use `read -s -p "Pancake API key: " PANCAKE_KEY`. To rotate the key,
use `gcloud secrets versions add pancake_pos --data-file=-` the same way. The service reads `:latest` when
a new revision starts.

**2. Deploy.** First run the offline checks
(`.venv/bin/python -m unittest tests.test_cloud_run_pancake_order` and
`uvx ruff@0.17.2 check src/cloud_run/cloud-run-pancake-order`). Cloud Build then builds the
folder's Dockerfile, which takes a few minutes:

```bash
gcloud run deploy pancake-order --source src/cloud_run/cloud-run-pancake-order \
  --project marine-cycle-484213-b4 --region asia-southeast1 --no-allow-unauthenticated \
  --update-secrets PANCAKE_API_KEY=pancake_pos:latest \
  --timeout 1800 --concurrency 1 --max-instances 1 --memory 1Gi
```

`--concurrency 1 --max-instances 1` stops two runs from overlapping and appending the same orders twice.

**3. Schedule.** The job `pancake-insert-raw_order` already exists: `GET /` daily at 07:20 Vietnam
time, 1800s deadline, 1 retry. Run `gcloud scheduler jobs list --location asia-southeast1` first, and
create a job only for a service that has none:

```bash
gcloud scheduler jobs create http <job-name> --project marine-cycle-484213-b4 --location asia-southeast1 \
  --schedule "20 7 * * *" --time-zone Asia/Ho_Chi_Minh --uri <service-url>/ --http-method GET \
  --attempt-deadline 1800s --max-retry-attempts 1 --min-backoff 600s
```

- Get `<service-url>` from
  `gcloud run services describe <service> --region asia-southeast1 --format="value(status.url)"`.
- Schedule after 07:00 Vietnam time. Raw tables are partitioned by UTC load time, and staging reads only
  today's Vietnam-date partition, so an earlier load is skipped downstream.
- These services have the invoker IAM check disabled, so jobs send no token. If a service enforces IAM,
  add `--oidc-service-account-email <sa>` and grant that account `roles/run.invoker` on the service.

**4. Smoke test without loading data.** This window predates the shop, so the service calls the Pancake
API once and writes nothing to BigQuery:

```bash
curl -sS -w "\nHTTP %{http_code}\n" "<service-url>/?start_date=2010-01-01T00:00:00&end_date=2010-01-01T00:00:01"
# Expected: "0 entry found. No data to export." and HTTP 200
```

**Check a scheduled run:**
`gcloud scheduler jobs describe pancake-insert-raw_order --location asia-southeast1 --project marine-cycle-484213-b4 --format="value(status,lastAttemptTime)"`
prints `{}` as the status when the last run succeeded. Logs are in the Cloud Run console. Every run
appends, so triggering the job or `/?start_date=…&end_date=…` for a window that's already loaded adds
duplicate rows.

## Security

- Credentials live only in `.env` (local) or Cloud Run environment variables / Secret Manager.
  `scripts/validate_repo.py` fails on the common hardcoded-credential patterns (a guardrail, not a
  complete secret scanner; still review diffs).
- `credentials/`, `.env`, `seeds/*.xlsx`, `data/` and notebook outputs are kept out of Git.
- Before publishing this repository, follow [docs/portfolio_checklist.md](docs/portfolio_checklist.md).
  The portfolio README draft is kept in [docs/portfolio-readme-template.md](docs/portfolio-readme-template.md).

## License

MIT unless the code belongs to an employer/client or other rights holder. See [LICENSE](LICENSE).
