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
.venv/bin/python scripts/validate_repo.py --imports  # import every Cloud Run service (isolated, offline)
```

## Security

- Credentials live only in `.env` (local) or Cloud Run environment variables / Secret Manager.
  `scripts/validate_repo.py` fails on the common hardcoded-credential patterns (a guardrail, not a
  complete secret scanner; still review diffs).
- `credentials/`, `.env`, `seeds/*.xlsx`, `data/` and notebook outputs are kept out of Git.
- Before publishing this repository, follow [docs/portfolio_checklist.md](docs/portfolio_checklist.md).
  The portfolio README draft is kept in [docs/portfolio-readme-template.md](docs/portfolio-readme-template.md).

## License

MIT unless the code belongs to an employer/client or other rights holder. See [LICENSE](LICENSE).
