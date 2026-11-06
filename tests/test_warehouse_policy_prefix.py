"""Warehouse policy rules decided on 2026-11-05 (D2, D3), checked offline against the JSON policy.

D2: a leading `CN –` / `TH –` / `VN –` in the warehouse's latest name decides its country.
D3: 480F Central Warehouse = B, TH Office Stock = M, VN Marketing Stock = M, VN Defective Stock = NONE.
The latest name is the last `→` segment of evidence_aliases; live names are re-checked read-only.
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = json.loads((ROOT / 'sql/config/warehouse_policy.json').read_text())
PREFIX_COUNTRY = {'CN': 'CHINA', 'TH': 'THAILAND', 'VN': 'VIETNAM'}
PREFIX = re.compile(r'^(CN|TH|VN)\s+[–-]\s+')


def latest_name(entry):
    return entry['evidence_aliases'].split('→')[-1].strip()


def prefix_country(name):
    match = PREFIX.match(name)
    return PREFIX_COUNTRY[match.group(1)] if match else None


class PrefixRuleTests(unittest.TestCase):
    def test_prefix_parser(self):
        self.assertEqual(prefix_country('CN – Backup Stock (VN)'), 'CHINA')
        self.assertEqual(prefix_country('TH - Office Stock'), 'THAILAND')
        self.assertIsNone(prefix_country('Kho MKT Thailand'))
        self.assertIsNone(prefix_country('VNX – not a prefix'))

    def test_every_prefixed_warehouse_maps_to_its_prefix_country(self):
        mismatches = [
            (e['warehouse_id'], latest_name(e), e['country'])
            for e in POLICY['warehouses']
            if prefix_country(latest_name(e)) not in (None, e['country'])
        ]
        self.assertEqual(mismatches, [])

    def test_prefixed_names_are_covered(self):
        # Guards the parser: the policy has prefixed warehouses for all three countries.
        countries = {prefix_country(latest_name(e)) for e in POLICY['warehouses']}
        self.assertTrue({'CHINA', 'THAILAND', 'VIETNAM'} <= countries)


class TypeDecisionTests(unittest.TestCase):
    def kind(self, name):
        found = [e['warehouse_type'] for e in POLICY['warehouses'] if latest_name(e) == name]
        self.assertEqual(len(found), 1, name)
        return found[0]

    def test_480f_central_warehouse_is_backup(self):
        self.assertEqual(self.kind('VN – Central Warehouse (480F)'), 'B')

    def test_office_and_marketing_stock_are_marketing(self):
        self.assertEqual(self.kind('TH – Office Stock'), 'M')
        self.assertEqual(self.kind('VN – Marketing Stock'), 'M')

    def test_defective_stock_is_none(self):
        self.assertEqual(self.kind('VN – Defective Stock'), 'NONE')


if __name__ == '__main__':
    unittest.main()
