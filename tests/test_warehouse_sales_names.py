"""Exercise the maintained sales name projections and joins on synthetic rows.

SQLite runs the actual simple SQL fragments; it does not emulate the financial
queries or prove GoogleSQL compilation. Full-body comparisons separately protect
every token outside the precisely allowed name-lookup change.
"""
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sql/live/bigquery/reportdb/routines'
FAMILIES = ('fn_sale_ecom_vn', 'fn_sale_online_vn', 'fn_sale_store_vn',
            'fn_sale_store_thai', 'fn_sale_wholeshale_vn')
OBJECTS = tuple(family + suffix for family in FAMILIES for suffix in ('', '_product', '_v2'))
DIMENSION = '`marine-cycle-484213-b4.core_pancake.core_warehouse`'


def source_path(name):
    return ROOT / 'sql/functions' / ('reportdb.' + name + '.sql')


def executable(sql):
    return re.sub(r'--[^\n]*', '', re.sub(r'/\*.*?\*/', '', sql, flags=re.S))


def source_sql(name):
    path = source_path(name)
    return executable((path if path.exists() else SNAPSHOT / (name + '.sql')).read_text())


def display_key(name):
    # The legacy wholesale base has only a header name, with no returned ID.
    return 'o' if name == 'fn_sale_wholeshale_vn' else 'oi'


def original_display(name):
    if (name == 'fn_sale_wholeshale_vn' or
            (not name.endswith('_v2') and any(name.startswith(family) for family in
             ('fn_sale_ecom_vn', 'fn_sale_online_vn', 'fn_sale_store_thai')))):
        return 'o.warehouse_name'
    return 'oi.warehouse_name'


def reviewed_join(alias, key):
    return (f'LEFT JOIN ( SELECT warehouse_id AS canonical_warehouse_id, '
            f'warehouse_name AS canonical_warehouse_name FROM {DIMENSION} '
            f') AS {alias} ON {alias}.canonical_warehouse_id = {key}.warehouse_id')


def restore_reviewed_name_changes(sql, name):
    """Undo ONLY these reviewed projections and exact lookup joins for comparison.

    A changed join type, table, key, condition, projection, or any extra join stays
    visible. This never discards arbitrary JOIN clauses or warehouse expressions.
    """
    sql = re.sub(r'\s+', ' ', executable(sql)).strip()
    sql = sql.replace(reviewed_join('warehouse', display_key(name)), '', 1)
    sql = sql.replace('warehouse.canonical_warehouse_name AS warehouse_name',
                      original_display(name), 1)
    if name.startswith(('fn_sale_store_vn', 'fn_sale_store_thai')):
        sql = sql.replace(reviewed_join('header_warehouse', 'o'), '', 1)
        count = 2 if name.startswith('fn_sale_store_thai') else 1
        sql = sql.replace('header_warehouse.canonical_warehouse_name', 'o.warehouse_name', count)
    return re.sub(r'\s+', ' ', sql).strip()


def projection_and_joins(sql):
    projection = re.findall(
        r'^\s*((?:o|oi)\.warehouse_name|warehouse\.canonical_warehouse_name AS warehouse_name),\s*$',
        sql, re.M)
    if len(projection) != 1:
        raise AssertionError(f'Expected exactly one name projection, got {projection}')
    joins = re.findall(
        r'LEFT JOIN \(\s*SELECT warehouse_id AS canonical_warehouse_id,\s*'
        r'warehouse_name AS canonical_warehouse_name\s*FROM '
        + re.escape(DIMENSION) + r'\s*\) AS (?:header_warehouse|warehouse)\s*'
        r'ON (?:header_warehouse|warehouse)\.canonical_warehouse_id = (?:o|oi)\.warehouse_id',
        sql)
    return projection[0], '\n'.join(joins).replace(DIMENSION, 'core_warehouse')


def evaluate_name(name, header_id='header', item_id='item', dimension_name='Current item',
                  header_name='Old header', item_name='Old item', expression=None):
    projection, joins = projection_and_joins(source_sql(name))
    if expression is not None:
        projection = expression
    with closing(sqlite3.connect(':memory:')) as db:
        db.execute('CREATE TABLE core_warehouse (warehouse_id TEXT PRIMARY KEY, warehouse_name TEXT)')
        db.executemany('INSERT INTO core_warehouse VALUES (?, ?)',
                       [('header', 'Current header'), ('item', dimension_name), ('other', 'Old item')])
        # Two facts exercise cardinality and additive quantities, not only string substitution.
        return db.execute(
            'WITH o(warehouse_id, warehouse_name) AS (VALUES (?, ?)), '
            'oi(warehouse_id, warehouse_name, quantity) AS (VALUES (?, ?, 2), (?, ?, 3)) '
            f'SELECT {projection}, oi.quantity FROM o CROSS JOIN oi {joins}',
            (header_id, header_name, item_id, item_name, item_id, item_name),
        ).fetchall()


class SalesNamesContract:
    """Shared assertions are instantiated once per family for focused checkpoints."""
    family = None

    def names(self):
        return [self.family + suffix for suffix in ('', '_product', '_v2')]

    def test_dimension_rename_and_header_item_disagreement(self):
        for name in self.names():
            for current in ('Current item', 'Renamed item', None):
                with self.subTest(function=name, dimension_name=current):
                    expected = 'Current header' if display_key(name) == 'o' else current
                    rows = evaluate_name(name, dimension_name=current)
                    self.assertEqual(rows, [(expected, 2), (expected, 3)])
                    self.assertEqual(sum(row[1] for row in rows), 5)

    def test_unknown_blank_and_null_identity_keep_rows_without_old_names(self):
        for name in self.names():
            for unknown in ('unknown', '', None):
                with self.subTest(function=name, warehouse_id=unknown):
                    args = {'header_id': unknown} if display_key(name) == 'o' else {'item_id': unknown}
                    self.assertEqual(evaluate_name(name, **args), [(None, 2), (None, 3)])

    def test_fact_name_changes_and_reused_names_do_not_change_lookup(self):
        for name in self.names():
            expected = 'Current header' if display_key(name) == 'o' else 'Current item'
            with self.subTest(function=name):
                self.assertEqual(evaluate_name(name, header_name=None, item_name='Old item'),
                                 [(expected, 2), (expected, 3)])
                self.assertEqual(evaluate_name(name, header_name='Renamed header', item_name=None),
                                 [(expected, 2), (expected, 3)])

    def test_modes_keep_deliberate_blank_warehouse_fields(self):
        sql = source_sql(self.family + '_v2')
        self.assertEqual(re.findall(r'AND i_type = (\d)', sql), ['0', '1', '3'])
        self.assertEqual(len(re.findall(r"''\s+warehouse_id,\s*''\s+warehouse_name", sql)), 2)
        self.assertIn('retail_price,warehouse_id,warehouse_name,', sql)

    def test_store_fallbacks_resolve_the_header_not_the_item(self):
        if 'store' not in self.family:
            return
        for name in self.names():
            cases = [case for case in re.findall(
                r'\bCASE\b(?:(?!\bCASE\b).)*?\bEND\b', source_sql(name), re.I | re.S)
                if re.search(r'warehouse_(?:name|id)', case)]
            with self.subTest(function=name):
                self.assertEqual(len(cases), 2 if self.family.endswith('_thai') else 1)
                for case in cases:
                    self.assertEqual(evaluate_name(name, expression=case),
                                     [('Current header', 2), ('Current header', 3)])
                    self.assertEqual(evaluate_name(name, header_id='unknown', expression=case),
                                     [(None, 2), (None, 3)])


for _family in FAMILIES:
    globals()[_family] = type(_family, (SalesNamesContract, unittest.TestCase), {'family': _family})


class SalesNameChangeBoundaryTests(unittest.TestCase):
    def test_wholesale_changes_only_the_reviewed_name_lookup(self):
        for suffix in ('', '_product', '_v2'):
            name = 'fn_sale_wholeshale_vn' + suffix
            with self.subTest(function=name):
                before = executable((SNAPSHOT / (name + '.sql')).read_text())
                before = re.sub(r'^CREATE\s+(?:OR\s+REPLACE\s+)?', 'CREATE ', before, count=1)
                after = restore_reviewed_name_changes(source_sql(name), name)
                after = re.sub(r'^CREATE\s+(?:OR\s+REPLACE\s+)?', 'CREATE ', after, count=1)
                self.assertEqual(re.sub(r'\s+', ' ', before).strip(), after)

    def test_normalizer_does_not_hide_wrong_lookup_or_extra_join(self):
        name = 'fn_sale_online_vn_v2'
        sql = source_sql(name)
        self.assertIn('warehouse.canonical_warehouse_id = oi.warehouse_id', sql)
        normalized = restore_reviewed_name_changes(sql, name)
        for bad in (sql.replace('warehouse.canonical_warehouse_id = oi.warehouse_id',
                                'warehouse.canonical_warehouse_id = o.warehouse_id'),
                    sql.replace('LEFT JOIN (', 'JOIN (', 1),
                    sql + '\nCROSS JOIN core_warehouse bad',
                    sql.replace('warehouse_name AS canonical_warehouse_name',
                                'warehouse_name AS canonical_warehouse_name, country', 1),
                    sql.replace(DIMENSION, '`marine-cycle-484213-b4.other.core_warehouse`', 1)):
            self.assertNotEqual(bad, sql)
            self.assertNotEqual(restore_reviewed_name_changes(bad, name), normalized)


if __name__ == '__main__':
    unittest.main()
