# 2026-10 restructure: migration notes

Branch `restructure` on top of the baseline commit on `main`. Goals: make the repo navigable for
engineers and AI agents, remove credentials from source code, and keep pipeline behavior unchanged.

## What changed

| Area | Change | Behavior impact |
|---|---|---|
| Git | Repository initialized; baseline commit on `main` | None |
| Credentials | Literals in 78 scripts → `os.environ["NAME"]` + `load_dotenv()`; values moved to gitignored `.env` | **Deploy impact**: see below |
| Notebooks | Git clean filter strips outputs (`scripts/nbstrip.py`, `.gitattributes`) | None on disk |
| SQL | Consolidated under `sql/` (mapping below); 3 byte-identical duplicates removed | None (nothing loads SQL by path) |
| Docs | New README, `docs/` pages, `sql/README.md`, `src/README.md`; old README kept as `docs/portfolio-readme-template.md` | None |
| Agents | `AGENTS.md`, `CLAUDE.md`, `.agents/skills/` (4 skills), `.claude/skills/` symlinks, `.claude/settings.json` | None |
| Tooling | `scripts/validate_repo.py`, `tests/` | None |
| Python layout | **Unchanged** (`src/cloud_run`, `src/local_run`, `src/csv_export`, `src/schema`) | None |

Python folders were deliberately not moved. Each Cloud Run folder is a Docker build context
referenced by external deploy commands, and `local_run/`/`schema/` compute paths from `__file__`
depth. Moving them would break those paths without a navigation benefit the docs don't already provide.

## Old → new paths

| Old path | New path |
|---|---|
| `models/staging/*` | `sql/staging/*` |
| `models/core/*` | `sql/core/*` |
| `models/marts/README.md`, `models/checks/README.md` | `sql/marts/README.md`, `sql/checks/README.md` |
| `models/.gitkeep` | removed (folder no longer empty) |
| `programmability/functions/*` | `sql/functions/*` |
| `programmability/functions/fn_assortment_seg_cont (1).sql` | removed (identical to `sql/functions/fn_assortment_seg_cont.sql`) |
| `programmability/procedures/*` | `sql/procedures/*` |
| `scripts/ad-hoc/*` | `sql/ad_hoc/*` |
| `scripts/archived_scripts/*` | `sql/archive/*` |
| `scripts/working_files/*` | `sql/working_files/*` |
| `sys-fn_money.sql`, `sys-udf_remove_vn_accents.sql` (root) | removed (identical copies in `sql/functions/`) |
| `README.md` (portfolio template) | `docs/portfolio-readme-template.md` (new `README.md` written) |
| `src/**` | unchanged |

## Credential environment variables

| Variable | Used by |
|---|---|
| `PANCAKE_API_KEY` | Pancake scripts (cloud_run, local_run, csv_export) |
| `DIANPLUS_APP_KEY`, `DIANPLUS_APP_SECRET` | Dianplus scripts |
| `DIANPLUS_TOKEN` | Dianplus CSV exporters, `local_run/dianplus_product.py` |
| `JUSHUITAN_APP_KEY`, `JUSHUITAN_APP_SECRET` | Jushuitan scripts |
| `MAGENTO_USERNAME`, `MAGENTO_PASSWORD` | Magento scripts |
| `SURFOSM_API_KEY` | Surfosm scripts |
| `META_ACCESS_TOKEN` | Cloud Run Meta services (and the Meta CSV exporter, which already read it) |
| `META_ACCESS_TOKEN_LOCAL` | `local_run/meta_ads_*.py` (a different token value today) |
| `TIKTOK_VN_ACCESS_TOKEN` | Cloud Run TikTok VN services |
| `TIKTOK_TH_ACCESS_TOKEN` | Cloud Run TikTok Thai services |
| `TIKTOK_ACCESS_TOKEN` | local_run/csv_export TikTok scripts (name already used by several of them) |

Where scripts used different values for the same system, each value got its own variable, so every
script still sends exactly the credential it sent before.

## Deployment impact

- **Running Cloud Run revisions are unaffected**; they keep the code they were built from.
- **The next deploy of any changed service needs its credential variables** set on the service
  (prefer Secret Manager: `--set-secrets NAME=secret:latest`). Without them:
  - Dianplus, Jushuitan, Magento, Meta, Surfosm and TikTok services read credentials at import, so
    the new revision **fails to start** (Cloud Run keeps serving the previous revision).
  - Pancake services start, but each request fails with `KeyError: 'PANCAKE_API_KEY'` (HTTP 500).
- Local runs: `load_dotenv()` finds the repo-root `.env`. Scripts that weren't changed (e.g. most TikTok
  local scripts) still need `set -a; source .env; set +a`.

## Required follow-ups (outside this repo)

1. **Rotate every credential** that was hardcoded (all 14 variables above). They were stored in
   plaintext source files and possibly in deployed images and Google Drive copies.
2. Create Secret Manager secrets and wire them into each Cloud Run service before its next deploy.
3. Update anything that referenced old SQL paths (bookmarks, Dataform repo copies, runbooks, the
   Google Drive `lsoul_document` folder that docstring deploy commands `cd` into).
4. Decide on the known issues in [troubleshooting.md](troubleshooting.md#known-issues), especially
   the broken `cloud-run-tiktok-thai-ads` runner and the duplicate `pancake-order_returned` service.
5. Each clone must configure the notebook filter (see [setup.md](setup.md#3-git-notebook-filter-once-per-clone)).

## Rollback

- **Undo the restructure but keep Git:** `git switch main` (baseline). Note the baseline has
  `__REDACTED_*__` markers instead of credentials, so it is a reference snapshot, not runnable code.
- **Undo a single step:** `git revert <commit>` on `restructure` (commits are small and independent:
  credentials → SQL move → tooling/docs/agents).
- **Restore the exact original folder** (including hardcoded credentials and notebook outputs):
  the full pre-restructure tree was archived outside the repo as
  `~/Downloads/lsoul-data-warehouse.pre-restructure-20261018.tar.gz` (mode 600, contains secrets; delete
  it after the credentials are rotated).
- The `.env` file created on 2026-10-18 holds the moved values; keep it until secrets are rotated.
