"""Execute warehouse decisions from maintained SQL against synthetic rows, offline.

SQLite evaluates the extracted standard SQL predicates/CASE expressions only. This
does not pretend to execute full BigQuery table functions or validate their joins.
"""
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import unittest

from test_warehouse_sales_names import restore_reviewed_name_changes


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sql/live/bigquery/reportdb/routines'
FAMILIES = {
    'fn_sale_ecom_vn': [
        ('3fb24787-3208-4fb7-9580-24a3754e51d6', 'Kho Ecommerce Việt Nam', 'VN – E-commerce Stock', []),
    ],
    'fn_sale_online_vn': [
        ('cf854971-c137-4e23-86ec-4bd8fbed6990', 'Kho Online', 'VN – Online Stock', []),
    ],
    'fn_sale_store_vn': [
        ('4a93fada-d892-4bbd-8547-ec505e6104df', 'Kho Nguyễn Trãi', 'VN – Nguyễn Trãi Store', ['Store Nguyễn Trãi']),
        ('c9aea4ce-e71e-404e-b7c1-8d6ff342d748', 'POP-UP OFFICE', 'Renamed pop-up', ['VN Pop-up']),
    ],
    'fn_sale_store_thai': [
        ('ad07f1c9-84be-4c4d-bc5b-4de980ffb97e', 'Kho Emsphere', 'TH – EmSphere Store', ['Store', 'Emsphere']),
        ('490ded40-64ba-4424-aaed-399abbf13fbb', 'Central Ladprao', 'Renamed Ladprao', ['Store', 'Central Ladprao']),
        ('133983a4-ff7d-4861-805c-0a1bdd51795f', 'Kho Central World', 'Renamed Central World', ['Store', 'Central World']),
    ],
}
OBJECTS = {
    family + suffix: family
    for family in FAMILIES for suffix in ('', '_product', '_v2')
}


def source_path(name):
    return ROOT / 'sql/functions' / ('reportdb.' + name + '.sql')


def executable(sql):
    # The selected bodies have no comment delimiters inside SQL string literals.
    sql = re.sub(r'/\*.*?\*/', '', sql, flags=re.S)
    return re.sub(r'--[^\n]*', '', sql)


def source_sql(name):
    path = source_path(name)
    # Allows the initial regression to demonstrate the actual old predicate, even
    # for deployed objects that did not yet have a maintained source file.
    return executable((path if path.exists() else SNAPSHOT / (name + '.sql')).read_text())


def warehouse_predicate(sql):
    clauses = re.findall(r'^\s*AND (.+warehouse_(?:id|name).+)$', sql, re.M)
    if len(clauses) != 1:
        raise AssertionError(f'Expected one warehouse-selection clause, got {clauses}')
    return clauses[0].strip()


def warehouse_cases(sql):
    return [case for case in re.findall(r'\bCASE\b(?:(?!\bCASE\b).)*?\bEND\b', sql, re.I | re.S)
            if re.search(r'warehouse_(?:name|id)', case)]


def evaluate(expression, warehouse_id, warehouse_name, source='', item_id='unrelated-item-warehouse',
             canonical_header_name='Canonical header warehouse'):
    with closing(sqlite3.connect(':memory:')) as db:
        return db.execute(
            'WITH o(warehouse_id, warehouse_name, order_sources_name) AS (VALUES (?, ?, ?)), '
            'oi(warehouse_id, warehouse_name) AS (VALUES (?, ?)), '
            'header_warehouse(canonical_warehouse_name) AS (VALUES (?)) '
            f'SELECT {expression} FROM o CROSS JOIN oi CROSS JOIN header_warehouse',
            (warehouse_id, warehouse_name, source, item_id, 'Item display name', canonical_header_name),
        ).fetchone()[0]


def normalize_nonwarehouse_sql(sql, name):
    sql = executable(sql)
    sql = restore_reviewed_name_changes(sql, name)
    sql = re.sub(r'^CREATE\s+(?:OR\s+REPLACE\s+)?', 'CREATE ', sql, count=1, flags=re.I)
    # Mask only the warehouse comparison operands, retaining Boolean operators,
    # CASE outputs and all unrelated query tokens for a full-body comparison.
    sql = re.sub(
        r"TRIM\(UPPER\(o\.warehouse_name\)\)\s+LIKE\s+'[^']*'"
        r"|o\.warehouse_(?:name|id)\s*(?:IN\s*\([^)]*\)|(?:=|LIKE)\s*'[^']*')",
        'WAREHOUSE_DECISION', sql, flags=re.I,
    )
    return re.sub(r'\s+', ' ', sql).strip()


class WarehouseFunctionIdentityTests(unittest.TestCase):
    def test_every_deployed_target_has_one_maintained_definition(self):
        for name in OBJECTS:
            with self.subTest(function=name):
                self.assertTrue(source_path(name).exists(), source_path(name))
                definitions = []
                pattern = rf'CREATE\s+OR\s+REPLACE\s+TABLE\s+FUNCTION\s+[^\n]*\b{re.escape(name)}\s*\('
                for path in (ROOT / 'sql/functions').rglob('*.sql'):
                    if re.search(pattern, executable(path.read_text()), re.I):
                        definitions.append(path)
                self.assertEqual(definitions, [source_path(name)])

    def test_renames_preserve_selection_but_copied_names_do_not(self):
        for name, family in OBJECTS.items():
            predicate = warehouse_predicate(source_sql(name))
            for warehouse_id, old_name, new_name, _ in FAMILIES[family]:
                with self.subTest(function=name, warehouse_id=warehouse_id):
                    for display_name in (old_name, new_name, 'Future unrelated label', None):
                        self.assertEqual(evaluate(predicate, warehouse_id, display_name), 1)
                    for other_id in ('unknown-warehouse', '', None):
                        self.assertFalse(evaluate(predicate, other_id, old_name))

    def test_order_header_identity_controls_membership(self):
        for name, family in OBJECTS.items():
            predicate = warehouse_predicate(source_sql(name))
            warehouse_id, old_name, _, _ = FAMILIES[family][0]
            with self.subTest(function=name):
                self.assertEqual(evaluate(predicate, warehouse_id, 'New label', item_id='other'), 1)
                self.assertFalse(evaluate(predicate, 'other', old_name, item_id=warehouse_id))

    def test_online_source_or_identity_is_preserved(self):
        for suffix in ('', '_product', '_v2'):
            name = 'fn_sale_online_vn' + suffix
            predicate = warehouse_predicate(source_sql(name))
            warehouse_id = FAMILIES['fn_sale_online_vn'][0][0]
            with self.subTest(function=name):
                for source in ('Website', 'Facebook', 'Webcake', 'Instagram', 'Zalo'):
                    self.assertEqual(evaluate(predicate, 'unknown', 'Unknown', source=source), 1)
                    self.assertEqual(evaluate(predicate, None, None, source=source), 1)
                self.assertEqual(evaluate(predicate, warehouse_id, None, source=None), 1)
                self.assertFalse(evaluate(predicate, 'unknown', 'Kho Online', source='Other'))
                self.assertFalse(evaluate(predicate, None, None, source=None))

    def test_store_report_labels_depend_on_identity(self):
        for name, family in OBJECTS.items():
            if 'store' not in family:
                continue
            cases = warehouse_cases(source_sql(name))
            for warehouse_id, old_name, new_name, labels in FAMILIES[family]:
                with self.subTest(function=name, warehouse_id=warehouse_id):
                    self.assertEqual(len(cases), len(labels))
                    for display_name in (old_name, new_name, None):
                        self.assertEqual([evaluate(case, warehouse_id, display_name) for case in cases], labels)
                    self.assertEqual([evaluate(case, 'unknown', old_name) for case in cases],
                                     ['Canonical header warehouse'] * len(labels))
                    self.assertEqual([evaluate(case, 'unknown', old_name, canonical_header_name=None)
                                      for case in cases], [None] * len(labels))

    def test_no_executable_name_comparisons_remain(self):
        for name in OBJECTS:
            with self.subTest(function=name):
                self.assertNotRegex(source_sql(name),
                                    r'warehouse_name\s*\)*\s*(?:IN\s*\(|LIKE\b|=)')

    def test_signatures_modes_outputs_and_other_logic_are_unchanged(self):
        for name in OBJECTS:
            with self.subTest(function=name):
                baseline = (SNAPSHOT / (name + '.sql')).read_text()
                proposed = source_sql(name)
                self.assertEqual(normalize_nonwarehouse_sql(proposed, name),
                                 normalize_nonwarehouse_sql(baseline, name))
                if name.endswith('_v2'):
                    self.assertEqual(re.findall(r'AND i_type = (\d)', proposed), ['0', '1', '3'])


if __name__ == '__main__':
    unittest.main()
