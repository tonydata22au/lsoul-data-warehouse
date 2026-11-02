"""Keep the complete name lineage covered, including SELECT-star consumers."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SALES = {
    family + suffix
    for family in ('fn_sale_ecom_vn', 'fn_sale_online_vn', 'fn_sale_store_vn',
                   'fn_sale_store_thai', 'fn_sale_wholeshale_vn', 'fn_sale_ecom_china',
                   'fn_sale_store_china', 'fn_sale_ecom_taobao_tmall_manual_china',
                   'fn_sale_ecom_thai')
    for suffix in ('', '_product', '_v2')
} | {'fn_sale_online_thai_product', 'fn_sale_online_thai_v2'}
INVENTORY = {
    'fn_china_product_inventory', 'fn_thailand_product_inventory',
    'fn_product_variations_warehouse_summary', 'fn_product_inventory_overseas_shipment',
    'fn_assortment_seg_cont_by_warehouse', 'fn_stats_product_v2',
    'fn_product_inventory_summary', 'fn_product_inventory_summary_v2',
}
INHERITED = {
    'fn_order_product_inventory_summary', 'fn_order_product_revenue_summary',
    'fn_order_revenue_summary', 'fn_order_sku_warehouse_master', 'fn_stats_product',
}
DOWNSTREAM = {
    'fn_order_master', 'fn_order_sku_master', 'fn_order_target_master',
    'fn_performance_snapshot', 'fn_performance_snapshot_v2',
    'fn_performance_snapshot_ai_generated_v2', 'fn_ads_spend_summary',
}


def executable(sql):
    return re.sub(r'--[^\n]*', '', re.sub(r'/\*.*?\*/', '', sql, flags=re.S))


class WarehouseNameCoverageTests(unittest.TestCase):
    def test_every_direct_target_is_declared_pending_and_reads_the_dimension(self):
        entries = json.loads((ROOT / 'sql/source_provenance.json').read_text())['sources']
        by_name = {entry['object'].split('.')[-1]: entry for entry in entries}
        for name in sorted(SALES | INVENTORY):
            with self.subTest(function=name):
                self.assertTrue(name in by_name, name + ' missing pending provenance')
                entry = by_name[name]
                self.assertEqual(entry['status'], 'pending')
                sql = executable((ROOT / entry['path']).read_text())
                self.assertIn('marine-cycle-484213-b4.core_pancake.core_warehouse', sql)
                self.assertNotRegex(sql, r"'[^']*Kho[^']*'\s+AS\s+warehouse_name")
                if name in SALES or name == 'fn_product_inventory_overseas_shipment':
                    self.assertNotRegex(sql, r'\b(?:o|oi)\.warehouse_name\b')

    def test_no_duplicate_deployable_function_definitions(self):
        definitions = {}
        for path in (ROOT / 'sql/functions').rglob('*.sql'):
            for name in re.findall(r'CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+FUNCTION\s+[^\s(]+\.(fn_\w+)`?\s*\(',
                                   executable(path.read_text()), re.I):
                definitions.setdefault(name, []).append(path.relative_to(ROOT))
        for name in SALES | INVENTORY:
            with self.subTest(function=name):
                self.assertEqual(len(definitions.get(name, [])), 1, definitions.get(name))

    def test_full_dependency_closure_includes_hidden_name_output(self):
        # Unchanged snapshot is the independent dependency baseline; functions added by
        # this migration retain signatures/callees and have explicit pending provenance.
        functions = {}
        for path in (ROOT / 'sql/live/bigquery/reportdb/routines').glob('*.sql'):
            sql = executable(path.read_text())
            if re.match(r'CREATE\s+TABLE\s+FUNCTION', sql, re.I):
                functions[path.stem] = sql
        closure = set(SALES | INVENTORY)
        while True:
            callers = {name for name, sql in functions.items()
                       if any(re.search(r'\b' + re.escape(dep) + r'`?\s*\(', sql)
                              for dep in closure)}
            if callers <= closure:
                break
            closure |= callers
        self.assertEqual(closure, SALES | INVENTORY | INHERITED | DOWNSTREAM)
        self.assertIn('fn_stats_product', closure)
        self.assertEqual(len(closure), 49)


if __name__ == '__main__':
    unittest.main()
