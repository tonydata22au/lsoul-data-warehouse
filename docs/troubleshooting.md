# Troubleshooting

## Common errors

| Symptom | Likely cause | Fix |
|---|---|---|
| `KeyError: 'PANCAKE_API_KEY'` (or another credential name) | The variable isn't set. Locally: missing from `.env` or the script doesn't load it. On Cloud Run: not configured on the service | Add it to `.env` / `set -a; source .env; set +a`; on Cloud Run set the env var or Secret Manager reference. Names are in [.env.example](../.env.example) |
| Cloud Run revision fails to start after a deploy | Module-level credential lookup (Dianplus, Jushuitan, Magento, Meta, Surfosm, TikTok scripts) raises `KeyError` at import | Configure all credential env vars for that service, then redeploy |
| `FileNotFoundError: …/credentials/google-credentials.json` from a `src/local_run/` script | Every `local_run/` script reads the key from `credentials/google-credentials.json` in the repo root and ignores `GOOGLE_APPLICATION_CREDENTIALS` | Put the service-account key at `credentials/google-credentials.json` (gitignored) in the repo root |
| `FileNotFoundError: …/src/credentials/google-credentials.json` from a `src/schema/` or `src/csv_export/` script | Those scripts default to `src/credentials/`, which doesn't exist | Set `GOOGLE_APPLICATION_CREDENTIALS` to your key's absolute path |
| HTTP 401/403 or "invalid token" from TikTok/Meta | Access token expired or revoked | Generate a new token, update `.env` and the Cloud Run secret |
| HTTP 500 with `cannot unpack non-iterable NoneType` | No data for the window: 10 services return `None` on empty days and the Flask route fails (see known issues) | Expected on empty days for those services; confirm in the source system |
| BigQuery `Provided Schema does not match` / field type errors | Table was created with non-STRING types or the API added a nested field | Loads cast everything to STRING and allow field addition; check the table schema against the schema script in `src/schema/` |
| Duplicate rows in raw tables | Expected: append-only loads with overlapping windows | Deduplicate downstream (core). Don't delete raw rows without agreement |
| Core table didn't update | `sp_*_insert` only loads when the newest staging partition is today's date (Vietnam time). Raw partitions use the UTC load time, so a `raw_pancake.raw_order` load before 07:00 ICT lands in yesterday's partition, which `stg_order` doesn't read | Check staging partitions and `sysdb.data_insert_log`; trigger loads after 07:00 ICT |
| "Yesterday" is off by a day | Jushuitan and Surfosm Cloud Run scripts use the container clock (UTC), not Vietnam time | Pass explicit dates |
| Notebooks always show as modified, or `git add` fails on notebooks | Notebook clean filter not configured, or `python3` missing | Run the `git config filter.nbstrip.*` commands in [setup.md](setup.md#3-git-notebook-filter-once-per-clone) |
| `validate_repo.py`: "literal assigned to 'API_KEY'" | A credential was hardcoded | Replace it with `os.environ["NAME"]` and add the name to `.env.example` |
| `validate_repo.py`: "no entry for <file>" | A pipeline file isn't listed in [pipelines.md](pipelines.md) | Add a row for it |

## Known issues

All of these existed before the 2026-10 restructure. They are documented, not fixed, because each
fix changes production behavior and needs a decision.

1. **`cloud-run-tiktok-thai-ads` can't start.** `app_runner.py` loads `cr-tiktok-thai-ads.py`, but the
   folder contains `cr-tiktok-ads.py`. Either the deployed image differs from this folder or the
   service is broken. (`scripts/validate_repo.py` tracks this in `KNOWN_BROKEN_SERVICES`.)
2. **`cloud-run-pancake-order_returned` duplicates `cloud-run-pancake-order`.** Its script was a
   byte-identical copy until `cloud-run-pancake-order` got the yesterday-only default,
   `updateStatus=updated_at` and the `notes`/`print_notes`/`tags` columns (instead of `ad_id`/`page_id`);
   the copy still has the 30-day window and the old column set. It fetches `/orders` and appends
   to `raw_pancake.raw_order`. If both are deployed,
   orders are loaded twice and nothing in Cloud Run fills `raw_pancake.raw_orders_returned`
   (`local_run/pancake_orders_returned.py` uses the right endpoint and table).
3. **`cloud-run-pancake-stats_product` and `cloud-run-pancake-stats_inventory_product`** call the
   same endpoint with the same parameters and load different tables.
4. **Empty days return HTTP 500** in pancake-ecom-product, pancake-order_returned,
   pancake-product, pancake-stats_inventory_product, pancake-stats_inventory_variations,
   pancake-stats_order, pancake-stats_product, pancake-variations, tiktok-ads and tiktok-thai-ads.
   (`pancake-order` now returns 200 "No data to export", because its one-day default window makes an
   empty window realistic.)
5. **Credential default paths point at folders that don't exist** in `src/schema/` and
   `src/csv_export/` (`src/credentials/`, `src/local-run/credentials/`, a Windows `G:` path in the
   warehouse-transfer schema script). `src/local_run/` no longer has this problem: it reads the
   repo-root `credentials/google-credentials.json`.
6. **Schema scripts drop live tables** when run, and `bq-raw_dianplus..order_return.py` creates
   `raw_dianplus_order_return` while loaders write `raw_dianplus_order_refund`.
7. **`CSV_V1_manual_jushuitan_taobao_tmall_order_manual.py`** reads from `<repo>/raw_data/`, which
   doesn't exist (the files are in `seeds/`).
8. **Docstring deploy commands are stale.** They reference folders outside the repo, and
   `cloud-run-tiktok-thai-gmv-max-report` would deploy over the VN service.
   `cloud-run-surfosm-inventory`'s example uses `--allow-unauthenticated`.
9. **SQL:** several objects are referenced but not defined in `sql/` (e.g.
   `sysdb.sp_data_insert_log_V3`), `stg_meta_ads_reporting_my.sql` reads a `stg_` table from `raw_meta`,
   and `core_pancake_orders_returned.sql` has an incomplete `BETWEEN`. See [../sql/README.md](../sql/README.md).
10. **Two different Meta tokens** are in use (`META_ACCESS_TOKEN` for Cloud Run,
    `META_ACCESS_TOKEN_LOCAL` for `local_run/meta_ads_*.py`). Confirm which is valid and consolidate.
