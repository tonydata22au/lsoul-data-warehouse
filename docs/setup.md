# Setup

## Prerequisites

- macOS/Linux shell, Git, Python 3.11 (the Cloud Run images use `python:3.11-slim`, except
  `cloud-run-pancake-order` on `python:3.13-slim`; the existing local `.venv` uses Python 3.13 and
  works for the offline checks and the service unit tests).
- Access to GCP project `marine-cycle-484213-b4` and a service-account key **only if** you will
  run pipelines locally (most code changes don't need it).

## 1. Python environment

```bash
python3.11 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt -r src/cloud_run/cloud-run-surfosm-inventory/requirements.txt
```

`requirements.txt` covers notebooks and BigQuery basics only. The pipeline runtime dependencies
(Flask, gunicorn, requests, pytz, pyarrow, pandas-gbq, python-dotenv, …) are declared per Cloud Run
service. All service `requirements.txt` files are identical except `cloud-run-surfosm-inventory`,
which adds `functions-framework` (installing that one gives the superset), and
`cloud-run-pancake-order`, which pins exact versions, uses `zoneinfo` + `tzdata` instead of `pytz`
and drops the unused `pandas-gbq`.

Version note: `requirements.txt` pins `pandas<3.0`, while the service files allow any `pandas>=2.0`
and the current local `.venv` has pandas 3.0.5. Cloud Run builds install the newest allowed version,
except `cloud-run-pancake-order`, pinned to the `.venv` versions (Python 3.13, pandas 3.0.5,
numpy 2.5.3). Its lint and format settings are in the folder's `ruff.toml`.

## 2. Credentials (local only)

```bash
cp -n .env.example .env   # -n never overwrites an existing .env (it may hold the only copy of the credentials)
chmod 600 .env
```

Fill in the variables you need. Every source credential is read with `os.environ["NAME"]`; a
missing one fails with `KeyError: 'NAME'`. Most scripts call `load_dotenv()`, which finds the
repo-root `.env`. **Exceptions** that don't load it, so export the variables in your shell first
(`set -a; source .env; set +a`):

- `src/local_run/tiktok_vn_ad_group.py`, `tiktok_vn_campaign.py`, `tiktok_vn_gmv_max.py` and all five
  `src/local_run/tiktok_thai_*.py` scripts (they only look for `src/local_run/.env`);
- `src/csv_export/CSV_V1_manual_tiktok_data_export_{ads,ad_group,campaign}.py`;
- `src/csv_export/CSV_V1_meta_ads_data_export_ads_insight` (reads `META_ACCESS_TOKEN`, `META_AD_ACCOUNT_ID`).

Exporting in the shell works for every script, so it's the simplest habit.

For BigQuery from your laptop, put your service-account key at `credentials/google-credentials.json`
in the repo root (the `credentials/` folder is gitignored). Every `src/local_run/` script reads the key
from there (resolved from the script's own location, so the working directory doesn't matter), ignores
`GOOGLE_APPLICATION_CREDENTIALS`, and fails at import if the file is missing.
`src/schema/` and `src/csv_export/` scripts still read `GOOGLE_APPLICATION_CREDENTIALS` and, when it's
unset, look for `src/credentials/google-credentials.json`, which doesn't exist in this repo.

Never commit `.env` or key files; `.gitignore` excludes them, and `scripts/validate_repo.py` flags
common hardcoded-credential patterns.

## 3. Git notebook filter (once per clone)

Notebook outputs contain business results, so Git stores notebooks without outputs:

```bash
git config filter.nbstrip.clean "python3 scripts/nbstrip.py"
git config filter.nbstrip.smudge cat
git config filter.nbstrip.required true
```

Your working copies keep their outputs; `git diff` shows only source changes.

## 4. Verify (offline)

```bash
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests
.venv/bin/python scripts/validate_repo.py --imports   # needs step 1; isolated from .env and the network
```

All three should pass. A warning about `cloud-run-tiktok-thai-ads` is expected (see
[troubleshooting.md](troubleshooting.md#known-issues)).

## Notebooks

```bash
.venv/bin/jupyter lab
```

The analysis notebooks were written for Google Colab (`google.colab` imports) and query BigQuery
directly; running them reads production data.
