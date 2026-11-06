"""Offline tests for the core_pancake load monitor and the repoint comparison tooling.

No BigQuery or gcloud calls: SQL is generated and inspected, verdict rules are exercised with
synthetic evidence. Live validation of the monitor against the 2026-11-06 run is recorded in
tasks/core-pancake-repoint-t7-report.md.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))

import compare_pancake_repoint as cmp  # noqa: E402
import monitor_core_pancake_load as mon  # noqa: E402

WRITE = re.compile(r'\b(INSERT\s+INTO|DELETE\s+FROM|UPDATE\s+`|MERGE\s+(INTO\s+)?`|CREATE\s|DROP\s|TRUNCATE\s|ALTER\s|CALL\s)', re.I)


class MonitorSqlIsReadOnly(unittest.TestCase):
    def test_snapshot_and_reconciliation_sql_only_read(self):
        sqls = [mon.snapshot_sql(), mon.snapshot_sql('2026-11-06 00:59:00')]
        sqls += [mon.reconcile_sql(m, '2026-11-05', '2026-11-06') for m in mon.MODELS]
        for sql in sqls:
            self.assertIsNone(WRITE.search(sql), sql[:200])

    def test_every_core_pancake_model_is_monitored(self):
        models = sorted(p.stem for p in (ROOT.parent / 'lsoul_dbt/models/core/pancake').glob('core_pancake__*.sql'))
        if not models:
            self.skipTest('lsoul_dbt checkout not found next to this repo')
        self.assertEqual(sorted(mon.MODELS), models)

    def test_keys_compare_positionally_across_differently_named_columns(self):
        # TO_JSON_STRING embeds field names: stage and core keys must share positional names.
        self.assertEqual(mon.key_expr(['inventory_history_id', 'current_inventory_warehouse_id']),
                         'TO_JSON_STRING(STRUCT(inventory_history_id AS k0, current_inventory_warehouse_id AS k1))')


class MonitorVerdicts(unittest.TestCase):
    ok_l3 = {m: 'OK' for m in mon.MODELS}
    wrote = {'jobs': 2, 'failed': 0}
    before = {'row_count': '100', 'distinct_keys': '100', 'null_keys': '0'}
    after = {'row_count': '105', 'distinct_keys': '105', 'null_keys': '0'}

    def rec(self, **kw):
        base = {'eligible': 5, 'missing': 0, 'mismatched': 0, 'duplicate_keys': 0, 'duplicate_rows': 0, 'null_keys': 0}
        base.update(kw)
        return base

    def status(self, rec, l3=None, l4=None, before=None, after=None, run_ok=True, model='core_pancake__order'):
        return mon.table_status(model, l3 or self.ok_l3, {model: self.wrote} if l4 is None else l4, rec,
                                before or self.before, after or self.after, run_ok)

    def test_pass_needs_eligible_rows_and_bigquery_write_evidence(self):
        self.assertEqual(self.status(self.rec()), 'PASS')
        self.assertEqual(self.status(self.rec(), l4={}), 'UNKNOWN')

    def test_missing_or_mismatched_keys_fail(self):
        self.assertEqual(self.status(self.rec(missing=1)), 'FAIL')
        self.assertEqual(self.status(self.rec(mismatched=3)), 'FAIL')

    def test_preexisting_null_keys_do_not_fail_but_new_ones_do(self):
        before = dict(self.before, null_keys='7')
        self.assertEqual(self.status(self.rec(null_keys=7), before=before), 'PASS')
        self.assertEqual(self.status(self.rec(null_keys=8), before=before), 'FAIL')

    def test_new_duplicates_fail(self):
        self.assertEqual(self.status(self.rec(duplicate_rows=1)), 'FAIL')

    def test_row_loss_fails_except_replace_by_date_model(self):
        shrunk = dict(self.after, row_count='90')
        self.assertEqual(self.status(self.rec(), after=shrunk), 'FAIL')
        self.assertEqual(self.status(self.rec(), after=shrunk, model='core_pancake__orders_returned'), 'PASS')

    def test_no_new_raw_partition_is_no_eligible_changes_not_pass(self):
        rec = self.rec(eligible=0, no_new_partitions=True)
        self.assertEqual(self.status(rec, l4={}), 'NO_ELIGIBLE_CHANGES')

    def test_failed_or_missing_run_is_never_pass(self):
        self.assertEqual(self.status(self.rec(), run_ok=False), 'UNKNOWN')
        self.assertEqual(self.status(self.rec(), l3=dict(self.ok_l3, core_pancake__order='ERROR')), 'FAIL')
        self.assertEqual(self.status(None), 'UNKNOWN')

    def test_dbt_log_parsing(self):
        log = '\n'.join([f'01:01:57  47 of 129 OK created sql incremental model core.{m} ... [MERGE (3 rows)]'
                         for m in mon.MODELS] + ['01:02:38  Done. PASS=130 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=130'])
        res = mon.dbt_results(log)
        self.assertTrue(res['__ok'])
        self.assertTrue(all(res[m] == 'OK' for m in mon.MODELS))
        self.assertFalse(mon.dbt_results(log.replace('ERROR=0', 'ERROR=1'))['__ok'])

    def test_dbt_failure_is_flagged_from_the_last_summary(self):
        freshness_then_failed_build = ('Done. PASS=21 WARN=0 ERROR=0 SKIP=0\n'
                                       'Done. PASS=120 WARN=0 ERROR=2 SKIP=8 NO-OP=0 TOTAL=130')
        res = mon.dbt_results(freshness_then_failed_build)
        self.assertTrue(res['__failed'])
        self.assertFalse(res['__ok'])

    def test_scheduled_execution_is_preferred_over_an_earlier_manual_run(self):
        listed = [{'metadata': {'name': 'manual', 'creationTimestamp': '2026-11-06T18:30:00Z'}},   # 01:30 ICT
                  {'metadata': {'name': 'scheduled', 'creationTimestamp': '2026-11-07T01:00:01Z'}}]  # 08:00 ICT
        original = mon.gcloud
        mon.gcloud = lambda *args: listed
        try:
            names = [e['metadata']['name'] for e in mon.execution_for(__import__('datetime').date(2026, 11, 7))]
        finally:
            mon.gcloud = original
        self.assertEqual(names, ['scheduled', 'manual'])


class ComparisonRewrite(unittest.TestCase):
    def test_nan_sums_on_both_sides_are_not_a_difference(self):
        self.assertTrue(cmp.close_enough('nan', 'nan'))
        self.assertFalse(cmp.close_enough('nan', '1.0'))
        self.assertTrue(cmp.close_enough('100.0000001', '100.0'))

    def test_parse_and_bind_typed_parameters(self):
        sql = ("CREATE OR REPLACE TABLE FUNCTION `p`.reportdb.fn_x(i_type INT64, i_from DATE)\n"
               "OPTIONS(description=\"it's (a) test\")\nAS\n-- don't\nSELECT i_type AS t, i_from AS f /* it's */;")
        name, params, body = cmp.parse_function(sql)
        self.assertEqual((name, params), ('fn_x', [('i_type', 'INT64'), ('i_from', 'DATE')]))
        self.assertEqual(cmp.bind(body, params, ['1', 'NULL']).strip(),
                         'SELECT CAST(1 AS INT64) AS t, CAST(NULL AS DATE) AS f')

    def test_old_query_calls_the_live_function(self):
        self.assertEqual(cmp.old_query('fn_dim_sku', ''), 'SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_dim_sku`()')

    def test_metrics_keep_duplicate_rows(self):
        self.assertIn('SUM(MOD(fp, 1000000007))', cmp.metrics_sql('SELECT 1'))
        self.assertNotIn('DISTINCT *', cmp.metrics_sql('SELECT 1'))


if __name__ == '__main__':
    unittest.main()
