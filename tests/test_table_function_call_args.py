"""Calls between reportdb table functions must match the callee's signature (offline).

BigQuery resolves a table-function call when the caller runs, not when it is created, so a
callee signature change breaks callers silently. Found 2026-11-06: fn_order_product_inventory_summary
still called fn_china_product_inventory(1, '') after the callee changed on 2026-06-26 from
(i_number_year_back INT64, i_warehouse STRING) to (i_type INT64, i_number_year_back INT64).

Checks every literal argument of every `reportdb.fn_*`(...) call in sql/functions and
sql/procedures: the count matches, a quoted literal goes only to a STRING parameter, and a bare
integer only to an INT64 parameter. Identifiers and expressions are not type-checked.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILES = sorted((ROOT / 'sql/functions').glob('*.sql')) + sorted((ROOT / 'sql/procedures').glob('*.sql'))

SIGNATURE = re.compile(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+FUNCTION\s+`?[\w.-]+`?\.?`?reportdb\.(fn_\w+)`?\s*\(([^()]*)\)',
    re.IGNORECASE | re.DOTALL)
CALL = re.compile(r'reportdb\.(fn_\w+)`?\s*\(([^()]*)\)', re.IGNORECASE)


def strip_comments(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.DOTALL)
    return re.sub(r'--[^\n]*', ' ', sql)


def split_args(text):
    return [a.strip() for a in text.split(',')] if text.strip() else []


def signatures():
    result = {}
    for path in FILES:
        match = SIGNATURE.search(strip_comments(path.read_text(encoding='utf-8')))
        if match:
            params = [p.split() for p in split_args(match.group(2))]
            result[match.group(1).lower()] = [p[1].upper() for p in params if len(p) >= 2]
    return result


def literal_type(arg):
    if re.fullmatch(r"'[^']*'|\"[^\"]*\"", arg):
        return 'STRING'
    if re.fullmatch(r'-?\d+', arg):
        return 'INT64'
    return None


def mismatches(sql, sigs):
    found = []
    body = SIGNATURE.sub(' ', strip_comments(sql))  # the CREATE header is not a call
    for match in CALL.finditer(body):
        name, args = match.group(1).lower(), split_args(match.group(2))
        if name not in sigs:
            continue
        params = sigs[name]
        if len(args) != len(params):
            found.append((name, match.group(2).strip(), f'{len(args)} args, signature has {len(params)}'))
            continue
        for arg, param in zip(args, params):
            kind = literal_type(arg)
            if kind and kind != param:
                found.append((name, match.group(2).strip(), f'{arg} is {kind}, parameter is {param}'))
    return found


class TableFunctionCallArgTests(unittest.TestCase):
    def test_checker_flags_a_string_literal_for_an_int64_parameter(self):
        sigs = {'fn_china_product_inventory': ['INT64', 'INT64']}
        sql = "FROM `p.reportdb.fn_china_product_inventory`(1,'') o"
        self.assertEqual(len(mismatches(sql, sigs)), 1)

    def test_checker_accepts_matching_literals_and_identifiers(self):
        sigs = {'fn_x': ['INT64', 'INT64', 'STRING']}
        self.assertEqual(mismatches("FROM `p.reportdb.fn_x`(0, i_number_year_back, '')", sigs), [])

    def test_signatures_are_parsed_from_the_repo(self):
        self.assertEqual(signatures()['fn_china_product_inventory'], ['INT64', 'INT64'])

    def test_every_reportdb_table_function_call_matches_its_signature(self):
        sigs = signatures()
        found = [(path.name, *m) for path in FILES for m in mismatches(path.read_text(encoding='utf-8'), sigs)]
        self.assertEqual(found, [])


if __name__ == '__main__':
    unittest.main()
