#!/usr/bin/env python3
"""Build read-only candidate SQL for unbuilt dbt Pancake models (core-pancake repoint, T7/T13).

The dbt changes (variations.images, orders_returned history, and the same model logic for the
others) are not built in BigQuery yet, so querying core.core_pancake__* would not test them.
This script renders a model's first-build SELECT offline with lsoul_dbt's own renderer
(scripts/lsoul_offline.py) for a given run date, inlines its staging refs, and maps sources
to what exists live today:

  * `raw`.`raw_*`                       -> `raw_pancake`.`raw_*`  (the raw-dataset move is not live yet)
  * `raw`.`raw_orders_returned_history` -> the freeze SELECT from core_pancake.core_orders_returned
    (sql/ad_hoc/q-freeze_pancake_orders_returned_history.sql, not run)

`--routine FILE` rewrites a routine file the same way: every core.core_pancake__<model> named in
--models becomes a parenthesised candidate subquery, and raw.* is mapped to raw_pancake.*. The output
is printed for a dry run or a read-only query. Nothing here connects to BigQuery or runs dbt.

Run with the dbt project's environment (jinja2, sqlglot):
  uv run --project ../lsoul_dbt python scripts/pancake_candidate_sql.py --model core_pancake__variations
  uv run --project ../lsoul_dbt python scripts/pancake_candidate_sql.py \
      --routine sql/functions/reportdb.fn_dim_sku.sql --models core_pancake__variations,core_pancake__product
The dbt repo is ../lsoul_dbt unless LSOUL_DBT_REPO is set. Run `dbt parse` there first (offline).
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DBT_REPO = Path(os.environ.get('LSOUL_DBT_REPO', ROOT.parent / 'lsoul_dbt')).resolve()
PROJECT = 'marine-cycle-484213-b4'
LIVE_RAW_DATASET = 'raw_pancake'
HISTORY_CUTOVER = '2026-02-11'
FREEZE_SELECT = (
    "SELECT TIMESTAMP('2026-11-05') AS _PARTITIONTIME, inserted_at, display_id, status, bill_full_name, "
    "customer_id, updated_at, creator_id, order_id, order_to_returned_id, is_duplicate "
    f"FROM `{PROJECT}.core_pancake.core_orders_returned` WHERE DATE(inserted_at) < DATE '{HISTORY_CUTOVER}'"
)

STAGE_REF = re.compile(r'`' + re.escape(PROJECT) + r'`\.`stage`\.`(stg_pancake__\w+)`')
RAW_REF = re.compile(r'`' + re.escape(PROJECT) + r'`\.`raw`\.`(raw_\w+)`')
HISTORY_REF = '`' + PROJECT + '`.`raw`.`raw_orders_returned_history`'


def strip_sql_comments(sql: str) -> str:
    return re.sub(r'(?m)^\s*--[^\n]*\n', '', sql)


def map_raw(sql: str) -> str:
    """Point raw sources at the datasets that exist live today."""
    sql = sql.replace(HISTORY_REF, '(' + FREEZE_SELECT + ')')
    sql = RAW_REF.sub(lambda m: f'`{PROJECT}`.`{LIVE_RAW_DATASET}`.`{m.group(1)}`', sql)
    # Plain (single-backtick) references, as written in routine files.
    sql = re.sub(r'`' + re.escape(PROJECT) + r'\.raw\.(raw_\w+)`',
                 lambda m: f'`{PROJECT}.{LIVE_RAW_DATASET}.{m.group(1)}`', sql)
    return sql


def inline_stage(sql: str, render) -> str:
    """Replace each stage ref with the rendered staging SELECT (staging views may be stale live)."""
    return STAGE_REF.sub(lambda m: '(\n' + strip_sql_comments(render(m.group(1))) + '\n)', sql)


def candidate(model: str, render) -> str:
    return map_raw(inline_stage(strip_sql_comments(render(model)), render))


def replace_core_refs(routine_sql: str, models: dict) -> str:
    """Swap core.core_pancake__<model> table references for candidate subqueries."""
    for name, sql in models.items():
        pattern = re.compile(r'`' + re.escape(PROJECT) + r'(?:\.core\.|`\.`core`\.`)' + name + r'`')
        routine_sql = pattern.sub(lambda _m, s=sql: '(\n' + s + '\n)', routine_sql)
    return map_raw(routine_sql)


def make_renderer(run_date: dt.date):
    sys.path.insert(0, str(DBT_REPO / 'scripts'))
    from lsoul_offline import Scenario, load_manifest, render_model  # noqa: E402

    manifest = load_manifest(DBT_REPO / 'target' / 'manifest.json')
    nodes = {n['name']: n for n in manifest['nodes'].values() if n.get('resource_type') == 'model'}
    started = dt.datetime.combine(run_date, dt.time(1, 0), tzinfo=dt.timezone.utc)
    scenario = Scenario(raw_max_partition=run_date.isoformat(), run_started_at=started,
                        target_name='prod', full_refresh=True)

    def render(name: str) -> str:
        return render_model(nodes[name], manifest, scenario)

    return render


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--run-date', default=dt.datetime.now(dt.timezone(dt.timedelta(hours=7))).date().isoformat(),
                        help='Vietnam run date the rendering assumes (default: today in Asia/Ho_Chi_Minh)')
    parser.add_argument('--model', help='print the candidate SELECT for this model')
    parser.add_argument('--routine', type=Path, help='rewrite this routine file with candidate subqueries')
    parser.add_argument('--models', default='', help='comma-separated core_pancake__* models to inline into --routine')
    args = parser.parse_args(argv)
    if not (args.model or args.routine):
        parser.error('give --model or --routine')
    render = make_renderer(dt.date.fromisoformat(args.run_date))
    if args.model:
        print(candidate(args.model, render))
    if args.routine:
        models = {m: candidate(m, render) for m in filter(None, args.models.split(','))}
        print(replace_core_refs(args.routine.read_text(encoding='utf-8'), models))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
