---
name: validate-changes
description: Validate any change to the LSOUL data warehouse repo before handing it back. Runs the offline checks (syntax, Cloud Run service wiring, hardcoded-credential scan, Markdown links, skills, pipeline inventory), the unittest suite and optional service import smoke tests, then reviews the diff for secrets and data. Use after editing pipelines, SQL, docs or agent files.
---

# Validate repository changes

## Purpose

Confirm a change is internally consistent and safe **without** calling source APIs or BigQuery.
These checks catch syntax errors, broken `app_runner.py` wiring, hardcoded credentials, broken
doc links, skill format errors and pipelines missing from the inventory. They can't prove that
a pipeline returns correct data; only an authorized run can (skill: `run-pipeline`).

## Prerequisites

- `python3` (3.9+) for the static checks and tests: standard library only.
- Optional, for `--imports`: the repo virtualenv with pipeline dependencies
  (`.venv/bin/python`, see [docs/setup.md](../../../docs/setup.md)).
- Git repository with the notebook filter configured (the check warns if it isn't).

## Relevant files

- [scripts/validate_repo.py](../../../scripts/validate_repo.py): all checks; `KNOWN_BROKEN_SERVICES` lists documented pre-existing defects.
- [tests/](../../../tests/): `test_validate_repo.py` (runs the static checks, tests the credential scanner), `test_nbstrip.py`.
- [docs/pipelines.md](../../../docs/pipelines.md): must name every pipeline file.

## Steps and commands (all supported today, all offline)

1. Static checks:
   ```bash
   python3 scripts/validate_repo.py
   ```
   Expected: every line `PASS`, exit code 0. One `warn:` for the known
   `cloud-run-tiktok-thai-ads` issue is normal.
2. Unit tests:
   ```bash
   python3 -m unittest discover -s tests
   ```
   Expected: `OK`.
3. If you touched anything under `src/cloud_run/`, import every service the way gunicorn does:
   ```bash
   .venv/bin/python scripts/validate_repo.py --imports
   ```
   Expected: `PASS check_service_imports` (plus the known tiktok-thai-ads warning). Each service is
   imported in a subprocess with `load_dotenv` disabled, dummy credentials, no Google credentials, a
   temporary `HOME`, and sockets blocked, so real secrets aren't read and any import-time network
   call fails the check.
4. For a changed `local_run/`, `csv_export/` or `schema/` script, `python3 -m py_compile <file>`.
   Don't execute it: importing those modules reads the service-account key, and running them calls APIs.
5. Review the diff:
   ```bash
   git status --short
   git diff --stat
   git diff
   ```
   Look for tokens, keys, passwords, customer names/phones/emails, query output, absolute
   personal paths, and changed BigQuery destinations or write dispositions you didn't intend.
6. If entry points, destinations, env vars or schedules changed, update
   [docs/pipelines.md](../../../docs/pipelines.md) and [.env.example](../../../.env.example), then rerun step 1.

## Validation of this skill's result

Report which commands you ran and their results. If a check fails, fix the cause; don't
add entries to `KNOWN_BROKEN_SERVICES` without the user's agreement.

## Operational limits

- Never run pipelines, SQL, `gcloud`, `bq`, or service URLs as "validation".
- `--imports` executes each service's module top level (imports, constants, Flask app creation).
  If it reports "network access attempted during import", a change added a network call at import
  time; report it rather than working around the block.
- The credential scan is a guardrail for common patterns (literals assigned to credential-named
  variables or used as env defaults), not a complete secret scanner.
- Notebooks are not executed or validated beyond the Git output filter.

## Proposed (not implemented)

- CI (e.g. GitHub Actions) running steps 1–2 on every push.
- A SQL linter/dry-run compile (`bq query --dry_run` still needs credentials and network, so
  it's an external call and needs authorization).
