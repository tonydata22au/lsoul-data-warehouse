# Troubleshooting

## Common errors

| Symptom | Likely cause | Fix |
|---|---|---|
| `KeyError: 'PANCAKE_API_KEY'` (or another credential name) | The variable isn't set. Locally: missing from `.env` or the script doesn't load it. On Cloud Run: not configured on the service | Add it to `.env` / `set -a; source .env; set +a`; on Cloud Run set the env var or Secret Manager reference. Names are in [.env.example](../.env.example) |
| Cloud Run revision fails to start after a deploy | Module-level credential lookup (Dianplus, Jushuitan, Magento, Meta, Surfosm, TikTok scripts) raises `KeyError` at import | Configure all credential env vars for that service, then redeploy |
| `FileNotFoundError: …/credentials/google-credentials.json` from a `src/local_run/` script | Every `local_run/` script reads the key from `credentials/google-credentials.json` in the repo root and ignores `GOOGLE_APPLICATION_CREDENTIALS` | Put the service-account key at `credentials/google-credentials.json` (gitignored) in the repo root |
| `FileNotFoundError: …/src/credentials/google-credentials.json` from a `src/schema/` or `src/csv_export/` script | Those scripts default to `src/credentials/`, which doesn't exist | Set `GOOGLE_APPLICATION_CREDENTIALS` to your key's absolute path |
| HTTP 401/403 or "invalid token" from TikTok/Meta | Access token expired or revoked | Generate a new token, update `.env` and the Cloud Run secret |
| HTTP 500 with `cannot unpack non-iterable NoneType` | No data for the window: on revisions deployed before the 2026-11-06 fix, 10 services return `None` on empty days and the Flask route fails (see known issues) | Expected on empty days for those services until redeployed; confirm in the source system |
| BigQuery `Provided Schema does not match` / field type errors | Table was created with non-STRING types or the API added a nested field | Loads cast everything to STRING and allow field addition; check the table schema against the schema script in `src/schema/` |
| Duplicate rows in raw tables | Expected: append-only loads with overlapping windows | Deduplicate downstream (core). Don't delete raw rows without agreement |
| Core table didn't update | `sp_*_insert` only loads when the newest staging partition is today's date (Vietnam time). Raw partitions use the UTC load time, so a `raw.raw_order` load before 07:00 ICT lands in yesterday's partition, which `stg_order` doesn't read | Check staging partitions and `sysdb.data_insert_log`; trigger loads after 07:00 ICT |
| "Yesterday" is off by a day | Jushuitan and Surfosm Cloud Run scripts use the container clock (UTC), not Vietnam time | Pass explicit dates |
| Notebooks always show as modified, or `git add` fails on notebooks | Notebook clean filter not configured, or `python3` missing | Run the `git config filter.nbstrip.*` commands in [setup.md](setup.md#3-git-notebook-filter-once-per-clone) |
| `validate_repo.py`: "literal assigned to 'API_KEY'" | A credential was hardcoded | Replace it with `os.environ["NAME"]` and add the name to `.env.example` |
| `validate_repo.py`: "no entry for <file>" | A pipeline file isn't listed in [pipelines.md](pipelines.md) | Add a row for it |

## Known issues

All of these existed before the 2026-10 restructure. Most are documented rather than fixed, because each
fix changes production behavior and needs a decision. Items marked **fixed locally** were fixed in the
working tree on 2026-11-06 and take effect only once the services are redeployed.

1. **`cloud-run-tiktok-thai-ads` couldn't start. Fixed locally on 2026-11-06, not deployed.** `app_runner.py`
   loaded `cr-tiktok-thai-ads.py`, but the folder contains `cr-tiktok-ads.py`; it now loads `cr-tiktok-ads.py`
   (no files renamed). A revision deployed before the fix still can't boot unless the deployed image differs
   from this folder. `KNOWN_BROKEN_SERVICES` in `scripts/validate_repo.py` is now empty.
2. **`cloud-run-pancake-order_returned` duplicates `cloud-run-pancake-order`.** Its script was a
   byte-identical copy until `cloud-run-pancake-order` got the yesterday-only default,
   `updateStatus=updated_at` and the `notes`/`print_notes`/`tags` columns (instead of `ad_id`/`page_id`);
   the copy still has the 30-day window and the old column set. It fetches `/orders` and appends
   to `raw.raw_order`. If both are deployed,
   orders are loaded twice and nothing in Cloud Run fills `raw.raw_orders_returned`
   (`local_run/pancake_orders_returned.py` uses the right endpoint and table).
3. **`cloud-run-pancake-stats_product` and `cloud-run-pancake-stats_inventory_product`** call the
   same endpoint with the same parameters and load different tables.
4. **Empty days return HTTP 500** in pancake-ecom-product, pancake-order_returned,
   pancake-product, pancake-stats_inventory_product, pancake-stats_inventory_variations,
   pancake-stats_order, pancake-stats_product, pancake-variations, tiktok-ads and tiktok-thai-ads.
   (`pancake-order` now returns 200 "No data to export", because its one-day default window makes an
   empty window realistic.) **Fixed locally on 2026-11-06, not deployed:** these now return 200 with the
   empty message and no load. Review before deploying: the scheduler stops retrying empty days.
5. **Credential default paths point at folders that don't exist** in `src/schema/` and
   `src/csv_export/` (`src/credentials/`, `src/local-run/credentials/`, a Windows `G:` path in the
   warehouse-transfer schema script). `src/local_run/` no longer has this problem: it reads the
   repo-root `credentials/google-credentials.json`.
6. **Schema scripts drop live tables** when run. (`bq-raw_dianplus..order_return.py` created
   `raw_dianplus_order_return` while loaders write `raw_dianplus_order_refund`; since 2026-11-06 it names
   `raw_dianplus_order_refund`, whose 85 columns it already matched.)
7. **`CSV_V1_manual_jushuitan_taobao_tmall_order_manual.py`** reads from `<repo>/raw_data/`, which
   doesn't exist (the files are in `seeds/`).
8. **Docstring deploy commands are stale.** They reference folders outside the repo, and
   `cloud-run-tiktok-thai-gmv-max-report` would deploy over the VN service.
   `cloud-run-surfosm-inventory`'s example uses `--allow-unauthenticated`.
9. **SQL:** several objects are referenced but not defined in `sql/` (e.g.
   `sysdb.sp_data_insert_log_V3`), `staging/stg_meta.stg_ads_reporting_my.sql` reads a `stg_` table (`stg_ads_reporting_my`, which doesn't exist) from the raw dataset,
   and `core/core_pancake.core_orders_returned.sql` has an incomplete `BETWEEN`. See [../sql/README.md](../sql/README.md).
10. **Two different Meta tokens** are in use (`META_ACCESS_TOKEN` for Cloud Run,
    `META_ACCESS_TOKEN_LOCAL` for `local_run/meta_ads_*.py`). Confirm which is valid and consolidate.
11. **Fetch failures reported as success.** On revisions deployed before 2026-11-06, a failed page, request
    error or API error code made the fetch loop stop and return what it had. So an outage looked like a
    valid empty day (200 "0 entries found"), and a mid-run failure loaded a partial window with 200. Affected:
    TikTok ×6, Dianplus ×4, jushuitan-order, magento-order. **Fixed locally (not deployed):** they now fail
    the run (500) before any load, which is safe to retry. **Still open (readiness blocker):**
    surfosm-order and surfosm-order_return skip any order whose detail request fails and load the rest
    with 200. See [raw-destination-contract.md](raw-destination-contract.md#http-and-cli-behaviour).
12. **Credentials in logs.** Dianplus (4 services) and jushuitan-order printed the signing "raw string",
    which starts with `DIANPLUS_APP_SECRET` / `JUSHUITAN_APP_SECRET`, and Jushuitan printed its `access_token`
    on every run. Cloud Run keeps stdout, so these secrets are in Cloud Logging: rotate them. **Fixed
    locally on 2026-11-06 in `cloud_run/` (not deployed):** the raw string is no longer printed and the
    request-param log masks credentials. `local_run/` and `csv_export/` still print the raw string to the
    terminal. **Still open:** on a failed request, Pancake (12 services, all except pancake-order) and Meta
    error text includes `api_key` / `access_token` (URL query), and a failed Dianplus auth includes
    `appSecret`. That text is returned in the 500 body and logged. Redact as pancake-order does
    (`redact_api_key`).
