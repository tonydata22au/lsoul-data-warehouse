#!/usr/bin/env python3
"""Old-vs-new comparison for the core_pancake -> core repoint (T7). Read-only; aggregates only.

For each reportdb table-function call in CALLS:
  * old = the live function, as deployed (reads core_pancake.core_*);
  * new = the repo file's body run as an ad-hoc SELECT: parameters replaced by the call's literals,
    nested reportdb calls inlined from their repo files (so the whole new call tree is evaluated),
    and the unbuilt dbt models replaced by candidate subqueries (scripts/pancake_candidate_sql.py:
    core_pancake__variations with images, core_pancake__orders_returned with history).
    The other core.core_pancake__* tables are read as built: their local dbt diff is only the raw
    dataset rename, so the built tables already carry the proposed logic.
Both sides are measured with the same query: row count, two order-independent hashes (BIT_XOR and a
sum mod p, which keeps duplicates), per-column numeric sums and distinct counts. No rows are printed.
Nothing is created or deployed. Each query has maximum_bytes_billed.

  uv run --project ../lsoul_dbt python scripts/compare_pancake_repoint.py OUTDIR [fn ...]
  python3 scripts/compare_pancake_repoint.py --print-new 'fn_dim_sku()'      # SQL only, no BigQuery

Writes OUTDIR/old.json, OUTDIR/new.json and OUTDIR/compare.json (metrics only).
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import math
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = 'marine-cycle-484213-b4'
MAX_BYTES = str(20 * 10**9)
NYB = [1, 3]
CANDIDATE_MODELS = ['core_pancake__variations', 'core_pancake__orders_returned']
# Fully inlined, this call tree exceeds BigQuery's planning limit ("too many subqueries"), so its nested
# reportdb calls stay on the live (old) definitions: only the function's own repoint is measured.
NESTED_LIVE = {'fn_product_inventory_summary_v2'}


def calls():
    """The 2026-11-05 baseline call set (thr_9b2q2q7sia) plus the objects repointed later."""
    c = {}
    simple = ['fn_sale_ecom_china', 'fn_sale_ecom_china_product', 'fn_sale_ecom_taobao_tmall_manual_china',
              'fn_sale_ecom_taobao_tmall_manual_china_product', 'fn_sale_ecom_thai', 'fn_sale_ecom_thai_product',
              'fn_sale_ecom_vn', 'fn_sale_ecom_vn_product', 'fn_sale_online_thai_product', 'fn_sale_online_vn',
              'fn_sale_online_vn_product', 'fn_sale_store_china', 'fn_sale_store_china_product', 'fn_sale_store_thai',
              'fn_sale_store_thai_product', 'fn_sale_store_vn', 'fn_sale_store_vn_product', 'fn_sale_wholeshale_vn',
              'fn_sale_wholeshale_vn_product', 'fn_product_inventory_overseas_shipment']
    for f in simple:
        c[f] = [f'{n}' for n in NYB]
    v2 = ['fn_sale_ecom_china_v2', 'fn_sale_ecom_taobao_tmall_manual_china_v2', 'fn_sale_ecom_thai_v2', 'fn_sale_ecom_vn_v2',
          'fn_sale_online_thai_v2', 'fn_sale_online_vn_v2', 'fn_sale_store_china_v2', 'fn_sale_store_thai_v2',
          'fn_sale_store_vn_v2', 'fn_sale_wholeshale_vn_v2']
    for f in v2:
        c[f] = [f'{n}, {t}' for n in NYB for t in (0, 1, 2, 3)]
    for f in ['fn_china_product_inventory', 'fn_thailand_product_inventory']:
        c[f] = [f'{t}, {n}' for t in (0, 1) for n in NYB]
    for f in ['fn_product_inventory_summary', 'fn_product_inventory_summary_v2']:
        c[f] = [f'{t}, 1, 30, NULL, NULL' for t in (0, 1)] + [f"{t}, 3, 90, DATE '2026-01-01', DATE '2026-10-31'" for t in (0, 1)]
    c['fn_product_variations_warehouse_summary'] = [f"{t}, 1, '{k}'" for t in (0, 1, 2) for k in ('', 'VIETNAM')]
    c['fn_stats_product_v2'] = [f'{t}, 1, 30, 1, NULL, NULL' for t in (0, 1)] + ["0, 3, 90, 1, DATE '2026-01-01', DATE '2026-10-31'"]
    c['fn_dim_sku'] = ['']
    # Added after the baseline: old fails live (signature bug, T11), so new is measured alone.
    c['fn_order_product_inventory_summary'] = ["0, 1, '', ''"]
    return c


# ---------------------------------------------------------------- SQL rewriting (offline)
def split_top(text: str):
    parts, depth, buf, q = [], 0, [], None
    for ch in text:
        if q:
            q = None if ch == q else q
        elif ch in "'\"`":
            q = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0 and not q:
            parts.append(''.join(buf).strip()); buf = []
        else:
            buf.append(ch)
    if ''.join(buf).strip():
        parts.append(''.join(buf).strip())
    return parts


def matching_paren(text: str, start: int) -> int:
    """Index of the ')' closing the '(' at start (quotes respected)."""
    depth, q = 0, None
    for i in range(start, len(text)):
        ch = text[i]
        if q:
            q = None if ch == q else q
        elif ch in "'\"`":
            q = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
    raise ValueError('unbalanced parentheses')


HEADER = re.compile(r'CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+FUNCTION\s+`?[\w.-]+`?\.?`?reportdb\.(fn_\w+)`?\s*\(', re.I)
CALL = re.compile(r'`' + re.escape(P) + r'(?:\.reportdb\.|`\.reportdb\.)(fn_\w+)`\s*\(')


def strip_comments(sql: str) -> str:
    """Remove -- and /* */ comments outside string literals (comments may hold quotes)."""
    out, i, q = [], 0, None
    while i < len(sql):
        ch = sql[i]
        if q:
            out.append(ch)
            if ch == '\\' and i + 1 < len(sql):
                out.append(sql[i + 1]); i += 2; continue
            if ch == q:
                q = None
        elif sql.startswith('--', i):
            j = sql.find('\n', i)
            i = len(sql) if j < 0 else j
            continue
        elif sql.startswith('/*', i):
            j = sql.find('*/', i + 2)
            i = len(sql) if j < 0 else j + 2
            out.append(' ')
            continue
        else:
            if ch in "'\"`":
                q = ch
            out.append(ch)
        i += 1
    return ''.join(out)


def parse_function(sql: str):
    """(name, [(param name, type)], body) of a CREATE TABLE FUNCTION file."""
    sql = strip_comments(sql)
    m = HEADER.search(sql)
    close = matching_paren(sql, m.end() - 1)
    params = [tuple(p.split()[:2]) for p in split_top(sql[m.end():close]) if p.strip()]
    rest = sql[close + 1:]
    opt = re.match(r'\s*(?:RETURNS\s+TABLE\s*<.*?>\s*)?OPTIONS\s*\(', rest, re.I | re.S)
    if opt:
        rest = rest[matching_paren(rest, opt.end() - 1) + 1:]
    body = re.sub(r'^\s*AS\b', '', rest, flags=re.I).strip().rstrip(';').strip()
    return m.group(1), params, body


def repo_function(name: str):
    return parse_function((ROOT / 'sql/functions' / f'reportdb.{name}.sql').read_text(encoding='utf-8'))


def bind(body: str, params, args):
    if len(params) != len(args):
        raise ValueError(f'{len(args)} args for {len(params)} params')
    for (name, typ), value in zip(params, args):
        # Typed like the TVF parameter, so NULL and literals keep the declared type.
        body = re.sub(r'(?<![\w.`])' + name + r'\b', lambda _m: f'CAST({value} AS {typ})', body)
    return body


def inline_calls(body: str, depth: int = 0) -> str:
    """Replace nested reportdb TVF calls with their bound repo bodies."""
    if depth > 6:
        raise RecursionError('reportdb call nesting deeper than 6')
    out, pos = [], 0
    for m in CALL.finditer(body):
        if m.start() < pos:
            continue
        close = matching_paren(body, m.end() - 1)
        args = split_top(body[m.end():close])
        _, params, inner = repo_function(m.group(1))
        out.append(body[pos:m.start()])
        out.append('(\n' + inline_calls(bind(inner, params, args), depth + 1) + '\n)')
        pos = close + 1
    out.append(body[pos:])
    return ''.join(out)


def new_query(fn: str, args: str, candidates: dict) -> str:
    sys.path.insert(0, str(ROOT / 'scripts'))
    from pancake_candidate_sql import replace_core_refs

    _, params, body = repo_function(fn)
    body = bind(body, params, split_top(args))
    if fn not in NESTED_LIVE:
        body = inline_calls(body)
    return replace_core_refs(body, candidates)


def old_query(fn: str, args: str) -> str:
    return f'SELECT * FROM `{P}.reportdb.{fn}`({args})'


def metrics_sql(source: str) -> str:
    return f"""WITH t AS ({source}), r AS (SELECT TO_JSON(t) AS j, FARM_FINGERPRINT(TO_JSON_STRING(t)) fp FROM t)
SELECT '__rows' k, CAST(COUNT(*) AS STRING) v FROM r
UNION ALL SELECT '__hash_xor', CAST(BIT_XOR(fp) AS STRING) FROM r
UNION ALL SELECT '__hash_sum', CAST(SUM(MOD(fp, 1000000007)) AS STRING) FROM r
UNION ALL SELECT CONCAT('sum:', k), FORMAT('%.6f', SUM(LAX_FLOAT64(j[k]))) FROM r, UNNEST(JSON_KEYS(j, 1)) k GROUP BY k HAVING COUNTIF(LAX_FLOAT64(j[k]) IS NOT NULL) > 0 AND COUNTIF(JSON_TYPE(j[k]) = 'number') > 0
UNION ALL SELECT CONCAT('ndv:', k), CAST(COUNT(DISTINCT TO_JSON_STRING(j[k])) AS STRING) FROM r, UNNEST(JSON_KEYS(j, 1)) k GROUP BY k
UNION ALL SELECT CONCAT('null:', k), CAST(COUNTIF(JSON_TYPE(j[k]) = 'null' OR j[k] IS NULL) AS STRING) FROM r, UNNEST(JSON_KEYS(j, 1)) k GROUP BY k"""


# ---------------------------------------------------------------- BigQuery (read-only)
def run(sql: str) -> dict:
    p = subprocess.run(['bq', 'query', f'--project_id={P}', '--location=asia-southeast1', '--use_legacy_sql=false',
                        '--format=json', '--max_rows=100000', f'--maximum_bytes_billed={MAX_BYTES}'],
                       input=sql, capture_output=True, text=True)
    if p.returncode:
        return {'__error': (p.stdout + p.stderr).strip()[-500:]}
    return {r['k']: r['v'] for r in json.loads(p.stdout or '[]')}


def close_enough(a: str, b: str) -> bool:
    try:
        x, y = float(a), float(b)
    except (TypeError, ValueError):
        return a == b
    if math.isnan(x) or math.isnan(y):  # SUM over a NaN column; NaN on both sides is not a difference
        return math.isnan(x) and math.isnan(y)
    return abs(x - y) <= 1e-6 * max(1.0, abs(x), abs(y))


def compare(old: dict, new: dict) -> dict:
    if '__error' in old or '__error' in new:
        return {'status': 'error', 'old_error': old.get('__error'), 'new_error': new.get('__error')}
    if all(old.get(k) == new.get(k) for k in ('__rows', '__hash_xor', '__hash_sum')):
        return {'status': 'equal'}
    diffs = {k: [old.get(k), new.get(k)] for k in sorted(set(old) | set(new))
             if not k.startswith('__hash') and not close_enough(old.get(k), new.get(k))}
    return {'status': 'equal_within_float_tolerance' if not diffs else 'different', 'diffs': diffs}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('outdir', nargs='?', type=Path)
    ap.add_argument('only', nargs='*')
    ap.add_argument('--print-new', help="print the new SQL for one call, e.g. 'fn_dim_sku()'; no BigQuery")
    ap.add_argument('--threads', type=int, default=6)
    a = ap.parse_args(argv)

    sys.path.insert(0, str(ROOT / 'scripts'))
    from pancake_candidate_sql import candidate, make_renderer
    import datetime as dt
    render = make_renderer(dt.datetime.now(dt.timezone(dt.timedelta(hours=7))).date())
    cands = {m: candidate(m, render) for m in CANDIDATE_MODELS}

    if a.print_new:
        fn, args = re.match(r'(\w+)\((.*)\)$', a.print_new).groups()
        print(new_query(fn, args, cands))
        return 0
    if not a.outdir:
        ap.error('OUTDIR is required unless --print-new is given')
    a.outdir.mkdir(parents=True, exist_ok=True)
    jobs = [(f, x) for f, xs in calls().items() if not a.only or f in a.only for x in xs]

    def one(job):
        fn, args = job
        key = f'{fn}({args})'
        try:
            new_sql = metrics_sql(new_query(fn, args, cands))
        except Exception as exc:  # rewrite failure is a result, not a crash
            return key, {'__error': f'rewrite: {exc}'}, {'__error': f'rewrite: {exc}'}
        o, n = run(metrics_sql(old_query(fn, args))), run(new_sql)
        if fn in NESTED_LIVE:
            n['__note'] = 'nested reportdb calls on live definitions'
        return key, o, n

    old, new, cmp_ = {}, {}, {}
    with cf.ThreadPoolExecutor(a.threads) as ex:
        for key, o, n in ex.map(one, jobs):
            old[key], new[key], cmp_[key] = o, n, compare(o, n)
            print(key, cmp_[key]['status'], o.get('__rows', 'ERR'), n.get('__rows', 'ERR'), flush=True)
    for name, data in (('old', old), ('new', new), ('compare', cmp_)):
        (a.outdir / f'{name}.json').write_text(json.dumps(data, indent=1, sort_keys=True))
    statuses = [c['status'] for c in cmp_.values()]
    print({s: statuses.count(s) for s in sorted(set(statuses))})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
