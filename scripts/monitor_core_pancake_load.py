#!/usr/bin/env python3
"""Read-only monitor for the scheduled dbt load of core.core_pancake__* (aggregates only).

  baseline  Snapshot each target table (rows, key counts, duplicates, null keys, newest business
            timestamp, last modified) and the dbt watermarks, before the scheduled run.
  post      Check five independent layers for one Vietnam run date and compare with the baseline:
              L1 the Cloud Scheduler trigger fired and a Cloud Run execution started that day;
              L2 the execution ran the expected image/GIT_COMMIT, target prod and `build --selector daily`;
              L3 dbt logged OK for every core_pancake__* model and finished with ERROR=0 SKIP=0;
              L4 BigQuery jobs by the dbt runner wrote each target table without error;
              L5 bounded source->target reconciliation over the raw partitions the run newly read
                 (watermark before -> after): missing keys, mismatched latest values, duplicate keys,
                 null keys, and row-count drops.
            Status per table: PASS, NO_ELIGIBLE_CHANGES ("Run succeeded; no eligible source changes"),
            FAIL or UNKNOWN. Missing evidence is UNKNOWN, never PASS.

Nothing is written to BigQuery or Cloud; it runs SELECTs (maximum_bytes_billed set) and gcloud
describe/list/log reads, and saves JSON with counts only (no rows) to --out.

  python3 scripts/monitor_core_pancake_load.py baseline --out DIR
  python3 scripts/monitor_core_pancake_load.py post --run-date 2026-11-07 --baseline DIR/baseline.json --out DIR
Runbook: docs/core-pancake-load-monitoring.md
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path

P = 'marine-cycle-484213-b4'
REGION = 'asia-southeast1'
JOB = 'dbt-daily-build'
TRIGGER = 'dbt-daily-build-trigger'
RUNNER = f'dbt-runner@{P}.iam.gserviceaccount.com'
MAX_BYTES = str(5 * 10**9)
VN = dt.timezone(dt.timedelta(hours=7))

# Verified 2026-11-06 against lsoul_dbt models/core/pancake (keys from the uniqueness tests,
# window/filters from the rendered SQL) and the live stage/core column lists.
# stg: staging view the model reads; keys: (stage expr, core column); value: compared on the newest
# stage row per key in the window (None: presence only); where: rows the model keeps.
MODELS = {
    'core_pancake__order': dict(
        stg='stg_pancake__order', keys=[('order_id', 'order_id')], value=('updated_at', 'updated_at'),
        biz='inserted_at', where='order_id IS NOT NULL'),
    'core_pancake__order_item': dict(
        stg='stg_pancake__order', keys=[('order_id', 'order_id'), ('order_item_id', 'order_item_id')],
        value=('updated_at', 'updated_at'), biz='order_date', where='order_item_id IS NOT NULL'),
    'core_pancake__customer': dict(
        stg='stg_pancake__customer', keys=[('customer_id', 'customer_id'),
                                           ('shop_customer_addresses_id', 'shop_customer_addresses_id')],
        value=('updated_at', 'updated_at'), biz='updated_at', where='customer_id IS NOT NULL'),
    'core_pancake__product': dict(
        stg='stg_pancake__product', keys=[('product_id', 'raw_product_id')], value=None,
        biz='updated_at', where='product_id IS NOT NULL'),
    'core_pancake__variations': dict(
        stg='stg_pancake__variations', keys=[('variation_id', 'variation_id')], value=('updated_at', 'updated_at'),
        biz='updated_at', where='variation_id IS NOT NULL'),
    'core_pancake__variation_warehouses': dict(
        stg='stg_pancake__variation_warehouses', keys=[('variation_id', 'variation_id'), ('warehouse_id', 'warehouse_id')],
        value=('actual_remain_qty', 'actual_remain_qty'), biz='updated_at',
        where="variation_id IS NOT NULL AND NULLIF(TRIM(warehouse_id), '') IS NOT NULL"),
    'core_pancake__warehouse': dict(
        stg='stg_pancake__inventory_histories', keys=[('warehouse_id', 'warehouse_id')], value=None,
        biz='updated_at', where="NULLIF(TRIM(warehouse_id), '') IS NOT NULL"),
    'core_pancake__inventory_histories': dict(
        stg='stg_pancake__inventory_histories', keys=[('inventory_history_id', 'inventory_history_id'),
                                                      ('current_inventory_warehouse_id', 'inv_warehouse_id')],
        value=None, biz='inserted_at', where='inventory_history_id IS NOT NULL'),
    'core_pancake__stats_inventory_variations': dict(
        stg='stg_pancake__stats_inventory_variations', keys=None, value=None, biz='inserted_at', where='TRUE'),
    'core_pancake__orders_returned': dict(
        stg='stg_pancake__orders_returned', keys=None, value=None, biz='inserted_at', where='order_id IS NOT NULL'),
}
# Uniqueness keys of the target tables (dbt tests); None = no row key (append / replace-by-date models).
TARGET_KEYS = {m: ([c for _, c in cfg['keys']] if cfg['keys'] else None) for m, cfg in MODELS.items()}
TARGET_KEYS['core_pancake__inventory_histories'] = ['inventory_history_id', 'inv_warehouse_id']


def bq(sql: str):
    p = subprocess.run(['bq', 'query', f'--project_id={P}', f'--location={REGION}', '--use_legacy_sql=false',
                        '--format=json', '--max_rows=10000', f'--maximum_bytes_billed={MAX_BYTES}'],
                       input=sql, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError((p.stdout + p.stderr).strip()[-600:])
    return json.loads(p.stdout or '[]')


def gcloud(*args: str):
    p = subprocess.run(['gcloud', *args, '--format=json'], capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(p.stderr.strip()[-600:])
    return json.loads(p.stdout or 'null')


def key_expr(cols, alias=''):
    # Positional field names, so stage and core keys compare even when the column names differ.
    return 'TO_JSON_STRING(STRUCT(' + ', '.join(f'{alias}{c} AS k{i}' for i, c in enumerate(cols)) + '))'


# ---------------------------------------------------------------- snapshot (baseline and post)
def snapshot_sql(as_of: str | None = None) -> str:
    """as_of: rebuild a past baseline with time travel (7 days) and the watermarks recorded by then."""
    travel = f" FOR SYSTEM_TIME AS OF TIMESTAMP('{as_of}')" if as_of else ''
    parts = []
    for model, cfg in MODELS.items():
        keys = TARGET_KEYS[model]
        k = key_expr(keys) if keys else 'NULL'
        null_k = ' OR '.join(f'{c} IS NULL' for c in keys) if keys else 'FALSE'
        parts.append(f"""SELECT '{model}' AS model, COUNT(*) AS row_count,
  COUNT(DISTINCT {k}) AS distinct_keys, COUNTIF({null_k}) AS null_keys,
  CAST(MAX({cfg['biz']}) AS STRING) AS max_business_ts
FROM `{P}.core.{model}`{travel}""")
    tables = "SELECT table_id AS model, TIMESTAMP_MILLIS(last_modified_time) AS last_modified FROM `" + P + ".core.__TABLES__` WHERE table_id LIKE 'core_pancake__%'"
    wm = ("SELECT REGEXP_EXTRACT(model_relation, r'[^.]+$') AS model, MAX(source_partition_time) AS watermark, "
          "ARRAY_AGG(invocation_id ORDER BY recorded_at DESC LIMIT 1)[OFFSET(0)] AS last_invocation, MAX(recorded_at) AS watermark_recorded_at "
          f"FROM `{P}.dbt_meta.incremental_watermark` WHERE model_relation LIKE '%.core.core_pancake__%'"
          + (f" AND recorded_at <= TIMESTAMP('{as_of}')" if as_of else '') + " GROUP BY 1")
    return (f"WITH s AS ({' UNION ALL '.join(parts)}), t AS ({tables}), w AS ({wm})\n"
            "SELECT s.*, CAST(t.last_modified AS STRING) AS last_modified, CAST(w.watermark AS STRING) AS watermark, "
            "w.last_invocation, CAST(w.watermark_recorded_at AS STRING) AS watermark_recorded_at "
            "FROM s LEFT JOIN t USING (model) LEFT JOIN w USING (model) ORDER BY model")


def snapshot(as_of: str | None = None):
    return {r['model']: r for r in bq(snapshot_sql(as_of))}


# ---------------------------------------------------------------- L5 reconciliation
def reconcile_sql(model: str, start: str, end: str) -> str:
    """Raw partitions with start < load_time <= end. Counts only."""
    cfg = MODELS[model]
    win = f"load_time > TIMESTAMP('{start}') AND load_time <= TIMESTAMP('{end}')"
    stg = f'`{P}.stage.{cfg["stg"]}`'
    tgt = f'`{P}.core.{model}`'
    if model == 'core_pancake__stats_inventory_variations':
        # Append model: SELECT DISTINCT of the window's stage rows, inserted_at = TIMESTAMP_TRUNC(proc_date, DAY).
        rows = (f"SELECT DISTINCT TIMESTAMP_TRUNC(proc_date, DAY) AS inserted_at, product_id, product_custom_id, "
                f"product_display_id, product_name, product_inserted_at, variation_custom_id, variation_display_id, "
                f"variation_fields, begin_inventory, end_inventory, total_import, total_export FROM {stg} WHERE {win}")
        return f"""WITH src AS ({rows}),
days AS (SELECT DISTINCT inserted_at FROM src),
t AS (SELECT COUNT(*) AS n FROM {tgt} WHERE inserted_at IN (SELECT inserted_at FROM days))
SELECT (SELECT COUNT(*) FROM src) AS eligible, (SELECT n FROM t) AS target_rows_for_window,
  GREATEST((SELECT COUNT(*) FROM src) - (SELECT n FROM t), 0) AS missing,
  0 AS mismatched, 0 AS duplicate_keys, (SELECT COUNTIF(inserted_at IS NULL) FROM {tgt}) AS null_keys"""
    if model == 'core_pancake__orders_returned':  # replace by inserted_at date from the newest load in the window
        return f"""WITH newest AS (SELECT * FROM {stg} WHERE {win} AND {cfg['where']}
                QUALIFY load_time = MAX(load_time) OVER ()),
src AS (SELECT DATE(inserted_at) AS day, COUNT(*) AS n FROM newest
      WHERE DATE(inserted_at) >= DATE_SUB((SELECT MAX(DATE(inserted_at)) FROM newest), INTERVAL 28 DAY) GROUP BY 1),
t AS (SELECT DATE(inserted_at) AS day, COUNT(*) AS n FROM {tgt} WHERE DATE(inserted_at) IN (SELECT day FROM src) GROUP BY 1)
SELECT (SELECT COUNT(*) FROM newest) AS eligible, (SELECT SUM(n) FROM t) AS target_rows_for_window,
  (SELECT COUNT(*) FROM src LEFT JOIN t USING (day) WHERE t.n IS NULL) AS missing,
  (SELECT COUNT(*) FROM src JOIN t USING (day) WHERE src.n != t.n) AS mismatched, 0 AS duplicate_keys,
  (SELECT COUNTIF(order_id IS NULL) FROM {tgt}) AS null_keys"""
    skeys = [s for s, _ in cfg['keys']]
    tkeys = [t for _, t in cfg['keys']]
    sk = key_expr(skeys)
    tk = key_expr(tkeys)
    val = cfg['value']
    latest = f"""latest AS (SELECT {sk} AS k{', CAST(' + val[0] + ' AS STRING) AS v' if val else ''} FROM {stg}
  WHERE {win} AND {cfg['where']}
  QUALIFY ROW_NUMBER() OVER (PARTITION BY {sk} ORDER BY load_time DESC{', ' + val[0] + ' DESC' if val else ''}) = 1)"""
    target = f"tgt AS (SELECT {tk} AS k{', CAST(' + val[1] + ' AS STRING) AS v' if val else ''} FROM {tgt})"
    null_t = ' OR '.join(f'{c} IS NULL' for c in tkeys)
    return f"""WITH {latest}, {target}
SELECT (SELECT COUNT(*) FROM latest) AS eligible,
  (SELECT COUNT(*) FROM latest JOIN tgt USING (k)) AS target_rows_for_window,
  (SELECT COUNT(*) FROM latest WHERE k NOT IN (SELECT k FROM tgt)) AS missing,
  {'(SELECT COUNT(*) FROM latest l JOIN tgt t USING (k) WHERE l.v IS DISTINCT FROM t.v)' if val else '0'} AS mismatched,
  (SELECT COUNT(*) FROM (SELECT k FROM tgt GROUP BY k HAVING COUNT(*) > 1)) AS duplicate_keys,
  (SELECT COUNT(*) - COUNT(DISTINCT k) FROM tgt) AS duplicate_rows,
  (SELECT COUNTIF({null_t}) FROM {tgt}) AS null_keys"""


# ---------------------------------------------------------------- L1-L4 (Cloud metadata, read-only)
def execution_for(run_date: dt.date):
    start = dt.datetime.combine(run_date, dt.time(0), VN)
    end = start + dt.timedelta(days=1)
    execs = gcloud('run', 'jobs', 'executions', 'list', f'--job={JOB}', f'--region={REGION}', '--limit=20') or []
    created = lambda e: dt.datetime.fromisoformat(e['metadata']['creationTimestamp'].replace('Z', '+00:00'))
    same_day = sorted((e for e in execs if start <= created(e) < end), key=created)
    # The scheduled execution starts at 08:00 ICT (plus up to 2 retried starts); a manual run earlier that day
    # must not be mistaken for it.
    window = (start + dt.timedelta(hours=7, minutes=55), start + dt.timedelta(hours=9, minutes=30))
    scheduled = [e for e in same_day if window[0] <= created(e) < window[1]]
    return scheduled + [e for e in same_day if e not in scheduled]


def execution_log(name: str) -> str:
    p = subprocess.run(['gcloud', 'logging', 'read',
                        f'resource.type="cloud_run_job" AND resource.labels.job_name="{JOB}" '
                        f'AND labels."run.googleapis.com/execution_name"="{name}"',
                        '--limit=2000', '--order=asc', '--freshness=3d', '--format=value(textPayload)'],
                       capture_output=True, text=True)
    return p.stdout


def dbt_results(log: str) -> dict:
    res = {}
    for m in MODELS:
        if re.search(rf'OK created sql \w+ model core\.{m} ', log):
            res[m] = 'OK'
        elif re.search(rf'(ERROR|FAIL)\S* .*core\.{m}\b', log):
            res[m] = 'ERROR'
        elif re.search(rf'SKIP .*core\.{m}\b', log):
            res[m] = 'SKIP'
        else:
            res[m] = 'NOT_FOUND'
    done = re.findall(r'Done\. PASS=(\d+) WARN=(\d+) ERROR=(\d+) SKIP=(\d+)', log)
    last = done[-1] if done else None  # the build's summary is the last one
    res['__summary'] = 'PASS={} WARN={} ERROR={} SKIP={}'.format(*last) if last else None
    res['__ok'] = bool(last and last[2] == '0' and last[3] == '0')
    res['__failed'] = bool(last and (last[2] != '0' or last[3] != '0'))
    return res


def bq_job_evidence(start_iso: str, end_iso: str) -> dict:
    rows = bq(f"""SELECT destination_table.table_id AS model, COUNT(*) AS jobs, COUNTIF(error_result IS NOT NULL) AS failed,
  STRING_AGG(DISTINCT statement_type) AS statements, SUM(IFNULL(dml_statistics.inserted_row_count, 0)) AS inserted,
  SUM(IFNULL(dml_statistics.updated_row_count, 0)) AS updated, SUM(IFNULL(dml_statistics.deleted_row_count, 0)) AS deleted
FROM `{P}`.`region-{REGION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time BETWEEN TIMESTAMP('{start_iso}') AND TIMESTAMP('{end_iso}')
  AND user_email = '{RUNNER}' AND destination_table.dataset_id = 'core'
  AND STARTS_WITH(destination_table.table_id, 'core_pancake__') AND state = 'DONE'
GROUP BY 1""")
    return {r['model']: r for r in rows}


# ---------------------------------------------------------------- verdicts
def table_status(model, l3, l4, rec, before, after, run_ok):
    if not run_ok or l3.get(model) != 'OK':
        return 'FAIL' if l3.get(model) in ('ERROR', 'SKIP') else 'UNKNOWN'
    if rec is None:
        return 'UNKNOWN'
    if rec.get('error'):
        return 'UNKNOWN'
    # Null keys and duplicate keys count only when the run added them (some exist in live data already).
    base_null = int((before or {}).get('null_keys') or 0)
    base_dup = int((before or {}).get('row_count') or 0) - int((before or {}).get('distinct_keys') or 0) if TARGET_KEYS[model] else 0
    new_null = int(rec['null_keys']) - base_null
    new_dup = int(rec.get('duplicate_rows', 0)) - base_dup if 'duplicate_rows' in rec else 0
    if new_null > 0 or new_dup > 0 or int(rec['missing']) > 0 or int(rec['mismatched']) > 0:
        return 'FAIL'
    if before and after and int(after['row_count']) < int(before['row_count']) and model not in (
            'core_pancake__orders_returned',):  # replace-by-date may shrink; others must not lose rows
        return 'FAIL'
    if rec.get('no_new_partitions'):
        return 'NO_ELIGIBLE_CHANGES'
    wrote = (l4 or {}).get(model)
    if not wrote or int(wrote['failed']) > 0:
        return 'UNKNOWN'  # no BigQuery write evidence for a run that had eligible changes
    return 'PASS' if int(rec['eligible']) > 0 else 'NO_ELIGIBLE_CHANGES'


def post(run_date: dt.date, baseline: dict, expected_commit: str | None) -> dict:
    out = {'run_date': run_date.isoformat(), 'layers': {}, 'tables': {}}
    trig = gcloud('scheduler', 'jobs', 'describe', TRIGGER, f'--location={REGION}')
    execs = execution_for(run_date)
    out['layers']['L1_scheduler'] = {
        'trigger_state': trig.get('state'), 'schedule': trig.get('schedule'), 'time_zone': trig.get('timeZone'),
        'last_attempt': trig.get('lastAttemptTime'), 'next': trig.get('scheduleTime'),
        'executions_that_day': [e['metadata']['name'] for e in execs],
        'ok': trig.get('state') == 'ENABLED' and bool(execs)}
    if not execs:
        out['verdict'] = 'UNKNOWN: no dbt-daily-build execution on this date (trigger paused, start failed, or not yet due)'
        return out
    ex = execs[0]
    name = ex['metadata']['name']
    status = ex.get('status', {})
    log = execution_log(name)
    first = next((ln for ln in log.splitlines() if ln.startswith('lsoul-dbt GIT_COMMIT=')), '')
    commit = re.search(r'GIT_COMMIT=(\S+)', first)
    out['layers']['L2_revision'] = {
        'execution': name, 'started': status.get('startTime'), 'completed': status.get('completionTime'),
        'succeeded': status.get('succeededCount'), 'failed': status.get('failedCount'),
        'image': ex['spec']['template']['spec']['containers'][0]['image'], 'first_log_line': first,
        'ok': bool(first) and 'target=prod' in first and first.endswith('args: build --selector daily')
              and (expected_commit is None or (commit and commit.group(1) == expected_commit))}
    l3 = dbt_results(log)
    out['layers']['L3_dbt'] = l3
    run_ok = bool(status.get('succeededCount')) and l3['__ok'] and out['layers']['L2_revision']['ok']
    run_failed = bool(status.get('failedCount')) or l3['__failed']
    end_iso = status.get('completionTime') or dt.datetime.now(dt.timezone.utc).isoformat()
    l4 = bq_job_evidence(status.get('startTime') or ex['metadata']['creationTimestamp'], end_iso)
    out['layers']['L4_bigquery_jobs'] = l4
    after = snapshot()
    out['snapshot_after'] = after
    for model in MODELS:
        b, a = baseline.get(model), after.get(model)
        rec = None
        if b and a and b.get('watermark') and a.get('watermark'):
            if a['watermark'] == b['watermark']:
                rec = {'no_new_partitions': True, 'eligible': 0, 'missing': 0, 'mismatched': 0,
                       'duplicate_keys': 0, 'null_keys': 0}
                keys = TARGET_KEYS[model]
                if keys:  # still check the table's integrity
                    r = bq(f"SELECT COUNT(*) - COUNT(DISTINCT {key_expr(keys)}) AS dup_rows, COUNTIF({' OR '.join(c + ' IS NULL' for c in keys)}) AS null_keys FROM `{P}.core.{model}`")[0]
                    rec['duplicate_keys'] = rec['duplicate_rows'] = r['dup_rows']
                    rec['null_keys'] = r['null_keys']
            else:
                try:
                    rec = bq(reconcile_sql(model, b['watermark'], a['watermark']))[0]
                    rec['window'] = [b['watermark'], a['watermark']]
                except RuntimeError as exc:
                    rec = {'error': str(exc)}
        status_ = table_status(model, l3, l4, rec, b, a, run_ok)
        out['tables'][model] = {'status': status_, 'dbt': l3.get(model), 'bq_jobs': l4.get(model),
                                'reconciliation': rec,
                                'rows_before': b and b['row_count'], 'rows_after': a and a['row_count'],
                                'watermark_before': b and b.get('watermark'), 'watermark_after': a and a.get('watermark')}
    statuses = [t['status'] for t in out['tables'].values()]
    out['verdict'] = ('FAIL' if run_failed or 'FAIL' in statuses else 'UNKNOWN' if 'UNKNOWN' in statuses
                      else 'PASS' if 'PASS' in statuses else 'Run succeeded; no eligible source changes')
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('mode', choices=['baseline', 'post', 'print-sql'])
    ap.add_argument('--out', type=Path, default=Path('.'))
    ap.add_argument('--run-date', help='Vietnam date of the scheduled run (post)')
    ap.add_argument('--baseline', type=Path, help='baseline.json from the baseline mode (post)')
    ap.add_argument('--as-of', help='baseline: rebuild the state at this UTC timestamp via time travel (<= 7 days ago)')
    ap.add_argument('--expected-commit', help='GIT_COMMIT the job should run (post; default: not checked)')
    a = ap.parse_args(argv)
    if a.mode == 'print-sql':
        print(snapshot_sql() + ';\n')
        for m in MODELS:
            print(f'-- {m}\n' + reconcile_sql(m, '2026-11-05', '2026-11-06') + ';\n')
        return 0
    a.out.mkdir(parents=True, exist_ok=True)
    if a.as_of:  # interpolated into SQL: accept only a timestamp
        a.as_of = dt.datetime.fromisoformat(a.as_of).strftime('%Y-%m-%d %H:%M:%S')
    if a.mode == 'baseline':
        snap = snapshot(a.as_of)
        path = a.out / 'baseline.json'
        path.write_text(json.dumps({'taken_at': dt.datetime.now(VN).isoformat(), 'as_of': a.as_of, 'tables': snap}, indent=1))
        print(json.dumps({m: {k: v for k, v in r.items() if k in ('row_count', 'watermark', 'last_modified')}
                          for m, r in snap.items()}, indent=1))
        print('saved', path)
        return 0
    if not (a.run_date and a.baseline):
        ap.error('post needs --run-date and --baseline')
    base = json.loads(a.baseline.read_text())['tables']
    result = post(dt.date.fromisoformat(a.run_date), base, a.expected_commit)
    path = a.out / f'post_{a.run_date}.json'
    path.write_text(json.dumps(result, indent=1, default=str))
    print('verdict:', result['verdict'])
    for m, t in result.get('tables', {}).items():
        rec = t['reconciliation'] or {}
        print(f"  {m:42} {t['status']:20} dbt={t['dbt']} eligible={rec.get('eligible')} missing={rec.get('missing')} "
              f"mismatched={rec.get('mismatched')} dup={rec.get('duplicate_keys')} rows {t['rows_before']}->{t['rows_after']}")
    print('saved', path)
    return 0 if result['verdict'] in ('PASS', 'Run succeeded; no eligible source changes') else 1


if __name__ == '__main__':
    raise SystemExit(main())
