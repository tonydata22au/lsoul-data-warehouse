"""Exercise overseas display expressions without executing production queries.

SQLite executes the extracted scalar lookups on synthetic dimensions. Its duplicate
scalar-row behavior differs from BigQuery: the duplicate test checks the lookup's
unreduced row set, not BigQuery's runtime error. Full-body comparison permits only
the exact reviewed display-expression replacement; joins, calculations and modes
must remain identical to the observed baseline (verified against live in Plan).
"""
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sql/live/bigquery/reportdb/routines'
DIMENSION = '`marine-cycle-484213-b4.core_pancake.core_warehouse`'
CHINA_ID = '76be7836-6dc5-4b1c-9e48-b18e43127453'
THAI_ID = '878504e9-fb75-4870-8504-b2ecdbc097ba'


def source_path(name):
    return ROOT / 'sql/functions' / ('reportdb.' + name + '.sql')


def executable(sql):
    # These reviewed bodies have no SQL comment markers inside string literals.
    return re.sub(r'--[^\n]*', '', sql)


def source_sql(name):
    path = source_path(name)
    # The observed definition makes the initial RED reproduce the old behavior
    # even for functions that do not yet have a maintained source file.
    return executable((path if path.exists() else SNAPSHOT / (name + '.sql')).read_text())


def display_expressions(sql):
    return re.findall(
        r"(?:^|,)\s*(\(SELECT\s+[^)]*\)|'[^'\n]+')\s+AS\s+warehouse_name\b",
        sql, re.I | re.M,
    )


def lookup_sql(warehouse_id):
    return (f'(SELECT w.warehouse_name FROM {DIMENSION} w '
            f"WHERE w.warehouse_id = '{warehouse_id}')")


def old_name(name):
    if '_china' in name:
        return 'Kho Trung Quốc (Back-up)'
    if name in ('fn_sale_ecom_thai', 'fn_sale_ecom_thai_v2'):
        return 'Kho Ecommerce Thailand'
    return 'Kho Thái (Back-up)'


def normalized(sql):
    sql = executable(sql)
    sql = re.sub(r'^CREATE\s+(?:OR\s+REPLACE\s+)?', 'CREATE ', sql, flags=re.I)
    return re.sub(r'\s+', ' ', sql).strip()


class OverseasNameContract:
    def expressions(self, name):
        expressions = display_expressions(source_sql(name))
        expected = 2 if name.startswith('fn_sale_ecom_china') else 1
        self.assertEqual(len(expressions), expected, name)
        return expressions

    def evaluate(self, expression, dimension_rows):
        with closing(sqlite3.connect(':memory:')) as db:
            db.execute('CREATE TABLE core_warehouse(warehouse_id TEXT, warehouse_name TEXT)')
            db.executemany('INSERT INTO core_warehouse VALUES (?, ?)', dimension_rows)
            return db.execute(
                'WITH facts(qty) AS (VALUES (2), (5)) '
                f'SELECT qty, {expression.replace(DIMENSION, "core_warehouse")} FROM facts'
            ).fetchall()

    def test_rename_updates_every_source_branch_without_changing_rows(self):
        for name in self.names:
            for expression in self.expressions(name):
                with self.subTest(function=name, expression=expression):
                    for label in ('Current dimension label', 'Future renamed label', None):
                        self.assertEqual(self.evaluate(expression, [
                            (self.warehouse_id, label),
                            ('unrelated-id', old_name(name)),
                        ]), [(2, label), (5, label)])

    def test_absent_id_keeps_rows_and_does_not_match_reused_name(self):
        for name in self.names:
            for expression in self.expressions(name):
                with self.subTest(function=name):
                    for other_id in ('unrelated-id', '', None):
                        self.assertEqual(self.evaluate(expression, [
                            (other_id, old_name(name)),
                        ]), [(2, None), (5, None)])

    def test_lookup_does_not_hide_duplicate_dimension_rows(self):
        for name in self.names:
            for expression in self.expressions(name):
                with self.subTest(function=name):
                    self.assertEqual(normalized(expression), normalized(lookup_sql(self.warehouse_id)))
                    with closing(sqlite3.connect(':memory:')) as db:
                        db.execute('CREATE TABLE core_warehouse(warehouse_id TEXT, warehouse_name TEXT)')
                        db.executemany('INSERT INTO core_warehouse VALUES (?, ?)', [
                            (self.warehouse_id, 'A'), (self.warehouse_id, 'B'),
                        ])
                        inner_query = expression.strip()[1:-1].replace(DIMENSION, 'core_warehouse')
                        self.assertEqual(db.execute(inner_query).fetchall(), [('A',), ('B',)])
                        # BigQuery rejects the two rows when evaluated as a scalar;
                        # do not silently use ANY_VALUE, LIMIT 1 or a multiplying JOIN.

    def test_only_reviewed_name_expressions_change(self):
        for name in self.names:
            with self.subTest(function=name):
                sql = source_sql(name)
                exact_lookup = re.escape(lookup_sql(self.warehouse_id)).replace(r'\ ', r'\s+')
                restored, count = re.subn(exact_lookup, repr(old_name(name)), sql)
                self.assertEqual(count, len(self.expressions(name)))
                self.assertEqual(normalized(restored), normalized((SNAPSHOT / (name + '.sql')).read_text()))

    def test_maintained_objects_are_unique_and_aggregate_modes_stay_blank(self):
        for name in self.names:
            with self.subTest(function=name):
                self.assertTrue(source_path(name).exists(), name)
                pattern = re.compile(r'CREATE\s+OR\s+REPLACE\s+TABLE\s+FUNCTION\s+[^\n]*\b' + re.escape(name) + r'\s*\(', re.I)
                paths = [p for p in (ROOT / 'sql/functions').rglob('*.sql') if pattern.search(p.read_text())]
                self.assertEqual(paths, [source_path(name)])
                sql = source_sql(name)
                if name.endswith('_v2'):
                    self.assertEqual(re.findall(r'AND i_type = (\d)', sql), ['0', '1', '3'])
                    self.assertEqual(len(re.findall(r"''\s+warehouse_id\s*,\s*''\s+warehouse_name", sql)), 2)


class ChinaEcommerceNamesTests(OverseasNameContract, unittest.TestCase):
    names = ['fn_sale_ecom_china' + suffix for suffix in ('', '_product', '_v2')]
    warehouse_id = CHINA_ID


class ChinaManualNamesTests(OverseasNameContract, unittest.TestCase):
    names = ['fn_sale_ecom_taobao_tmall_manual_china' + suffix for suffix in ('', '_product', '_v2')]
    warehouse_id = CHINA_ID


class ChinaStoreNamesTests(OverseasNameContract, unittest.TestCase):
    names = ['fn_sale_store_china' + suffix for suffix in ('', '_product', '_v2')]
    warehouse_id = CHINA_ID


class ThaiEcommerceNamesTests(OverseasNameContract, unittest.TestCase):
    names = ['fn_sale_ecom_thai' + suffix for suffix in ('', '_product', '_v2')]
    warehouse_id = THAI_ID


class ThaiOnlineNamesTests(OverseasNameContract, unittest.TestCase):
    names = ['fn_sale_online_thai' + suffix for suffix in ('_product', '_v2')]
    warehouse_id = THAI_ID


if __name__ == '__main__':
    unittest.main()
