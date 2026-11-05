"""Execute the procedure's relational SQL on synthetic rows using SQLite.

Only BigQuery date/UDF spellings and MERGE syntax are adapted. This verifies the
actual SELECT/update expressions, not a second Python implementation. BigQuery
procedure compilation/transaction behavior still needs service-side verification.
"""
import json
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROCEDURE = ROOT / 'sql/procedures/core_pancake.sp_pancake_core_warehouse_insert.sql'
POLICY = ROOT / 'sql/config/warehouse_policy.json'
THAI = 'ad07f1c9-84be-4c4d-bc5b-4de980ffb97e'
MARKETING = '66184c11-4f37-465b-b5a7-09cb026b9ebd'


def sqlite_sql(sql):
    sql = re.sub(r'`marine-cycle-484213-b4\.(?:stg_pancake|core_pancake)\.(\w+)`', r'\1', sql)
    sql = sql.replace('`marine-cycle-484213-b4.sysdb.udf_remove_vn_accents`', 'warehouse_code')
    sql = sql.replace("CURRENT_DATETIME('Asia/Ho_Chi_Minh')", "'2026-11-02 12:00:00'")
    sql = sql.replace("CURRENT_DATE('Asia/Ho_Chi_Minh')", "DATE('2026-11-02')")
    sql = sql.replace('CURRENT_DATE()', "DATE('2026-11-02')")
    sql = re.sub(r"DATE_SUB\(DATE\('2026-11-02'\), INTERVAL (\d+) DAY\)",
                 r"DATE('2026-11-02', '-\1 day')", sql)
    sql = sql.replace("DATE_DIFF(DATE('2026-11-02'), MAX(DATE(i.inserted_at)), DAY)",
                      "(JULIANDAY('2026-11-02') - JULIANDAY(MAX(DATE(i.inserted_at))))")
    return sql.replace('data_proc_date', "DATE('2026-11-02')")


class WarehouseDimensionTests(unittest.TestCase):
    def setUp(self):
        self.sql = PROCEDURE.read_text()
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        self.db.row_factory = sqlite3.Row
        self.db.create_function('warehouse_code', 1, lambda name: None if name is None else 'code:' + name)
        self.db.executescript('''
            CREATE TABLE stg_inventory_histories (
                proc_date TEXT, inserted_at TEXT, inventory_history_id TEXT,
                warehouse_id TEXT, warehouse_name TEXT);
            CREATE TABLE core_warehouse (
                warehouse_id TEXT, warehouse_code TEXT, warehouse_name TEXT,
                country TEXT, warehouse_type TEXT, is_active INTEGER,
                inserted_at TEXT, updated_at TEXT);
            CREATE TABLE core_inventory_histories (warehouse_id TEXT, inserted_at TEXT);
        ''')

    def section(self, name):
        match = re.search(r'-- BEGIN ' + name + r'\n(.*?)-- END ' + name, self.sql, re.S)
        self.assertIsNotNone(match, 'Procedure must expose the executable ' + name + ' SQL section')
        return match.group(1).strip()

    def add_source(self, key=THAI, name='TH – EmSphere Store', event='2026-11-01 10:00:00',
                   load='2026-11-02 07:00:00', event_id='event-1'):
        self.db.execute('INSERT INTO stg_inventory_histories VALUES (?, ?, ?, ?, ?)',
                        (load, event, event_id, key, name))

    def add_target(self, key=THAI, name='Old name', country='VIETNAM', kind='P', active=1):
        self.db.execute('INSERT INTO core_warehouse VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                        (key, 'code:' + name, name, country, kind, active, '2026-10-01', '2026-10-01'))

    def run_refresh(self):
        precondition = re.search(r'ASSERT \(\s*(SELECT.*?)\s*\) AS', self.sql, re.S).group(1)
        precondition = precondition.replace("COUNTIF(warehouse_id IS NULL OR TRIM(warehouse_id) = '')",
                                             "COUNT(*) FILTER (WHERE warehouse_id IS NULL OR TRIM(warehouse_id) = '')")
        if not self.db.execute(sqlite_sql(precondition)).fetchone()[0]:
            raise ValueError('core_warehouse requires unique, nonempty warehouse IDs before refresh')
        policy = self.section('WAREHOUSE POLICY')
        self.execute_temp(policy)
        if self.db.execute("SELECT MAX(DATE(proc_date)) = '2026-11-02' FROM stg_inventory_histories").fetchone()[0]:
            self.execute_temp(self.section('WAREHOUSE SOURCE'))
            merge = self.section('WAREHOUSE MERGE')
            update = re.search(r'WHEN MATCHED THEN UPDATE SET\s+(.*?)\s+WHEN NOT MATCHED', merge, re.S).group(1)
            self.db.execute(sqlite_sql('UPDATE core_warehouse AS target SET ' + update +
                                      ' FROM warehouse_source AS source WHERE target.warehouse_id = source.warehouse_id'))
            insert = re.search(r'WHEN NOT MATCHED THEN INSERT\s*\((.*?)\)\s*VALUES\s*\((.*?)\)\s*;', merge, re.S)
            self.db.execute(sqlite_sql('INSERT INTO core_warehouse (' + insert.group(1) + ') SELECT ' +
                                      insert.group(2) + ' FROM warehouse_source AS source LEFT JOIN core_warehouse AS target '
                                      'ON target.warehouse_id = source.warehouse_id WHERE target.warehouse_id IS NULL'))
        self.db.execute(sqlite_sql(self.section('WAREHOUSE CLASSIFICATION')))
        self.db.execute(sqlite_sql(self.section('WAREHOUSE ACTIVITY')))

    def execute_temp(self, sql):
        # SQLite's equivalent of BigQuery's replacement of a script-local temp table.
        if sql.startswith('CREATE OR REPLACE TEMP TABLE '):
            table = re.match(r'CREATE OR REPLACE TEMP TABLE (\w+)', sql).group(1)
            self.db.execute('DROP TABLE IF EXISTS ' + table)
            sql = sql.replace('CREATE OR REPLACE TEMP TABLE', 'CREATE TEMP TABLE', 1)
        self.db.execute(sqlite_sql(sql))

    def row(self, key=THAI):
        return self.db.execute('SELECT * FROM core_warehouse WHERE warehouse_id = ?', (key,)).fetchone()

    def test_rename_and_duplicate_events_produce_one_latest_row(self):
        self.add_source(name='Kho Emsphere', event='2026-10-24 10:00:00')
        self.add_source()
        self.add_source()
        self.run_refresh()
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM core_warehouse').fetchone()[0], 1)
        self.assertEqual(self.row()['warehouse_name'], 'TH – EmSphere Store')
        self.assertEqual((self.row()['country'], self.row()['warehouse_type']), ('THAILAND', 'P'))

    def test_latest_load_precedes_event_date_and_ties_are_deterministic(self):
        self.add_source(name='Old observation', load='2026-11-02 06:00:00', event='2026-11-02 10:00:00')
        self.add_source(name='Z name', event_id='event-2')
        self.add_source(name='A name', event_id='event-3')
        self.run_refresh()
        self.assertEqual(self.row()['warehouse_name'], 'A name')

    def test_null_or_blank_name_carries_forward_existing_display(self):
        self.add_target()
        self.add_source(name=None)
        self.add_source(name='  ')
        self.run_refresh()
        self.assertEqual((self.row()['warehouse_name'], self.row()['warehouse_code']), ('Old name', 'code:Old name'))
        self.assertEqual(self.row()['country'], 'THAILAND')

    def test_recent_nonblank_source_name_survives_later_null_observation(self):
        self.add_source(name='New valid label')
        self.add_source(name=None, load='2026-11-02 08:00:00')
        self.run_refresh()
        self.assertEqual(self.row()['warehouse_name'], 'New valid label')

    def test_unknown_id_does_not_inherit_classification_from_copied_name(self):
        self.add_source(key='unknown-id', name='Kho Offfice Thailand')
        self.add_source(key=None)
        self.add_source(key='  ')
        self.run_refresh()
        row = self.row('unknown-id')
        self.assertEqual((row['country'], row['warehouse_type']), ('VIETNAM', 'P'))
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM core_warehouse').fetchone()[0], 1)

    def test_missing_staging_still_corrects_absent_known_warehouse(self):
        self.add_target(key=MARKETING)
        self.run_refresh()
        self.assertEqual(self.row(MARKETING)['warehouse_type'], 'M')
        self.assertEqual(self.row(MARKETING)['warehouse_name'], 'Old name')

    def test_stale_staging_does_not_overwrite_name_but_activity_expires(self):
        self.add_target()
        self.add_source(name='Stale source', load='2026-11-01 07:00:00')
        self.db.execute('INSERT INTO core_inventory_histories VALUES (?, ?)', (THAI, '2026-10-01'))
        self.run_refresh()
        self.assertEqual(self.row()['warehouse_name'], 'Old name')
        self.assertEqual(self.row()['is_active'], 0)

    def test_thirty_day_boundary_is_active_and_recent_input_reactivates(self):
        self.add_target(active=0)
        self.add_source(event='2026-10-03 12:00:00')
        self.db.execute('INSERT INTO core_inventory_histories VALUES (?, ?)', (THAI, '2026-10-03'))
        self.run_refresh()
        self.assertEqual(self.row()['is_active'], 1)
        self.assertEqual(self.row()['inserted_at'], '2026-11-01 00:00:00')

    def test_policy_sql_matches_versioned_config(self):
        self.execute_temp(self.section('WAREHOUSE POLICY'))
        actual = {tuple(row) for row in self.db.execute('SELECT warehouse_id, country, warehouse_type FROM warehouse_policy')}
        policy = json.loads(POLICY.read_text())
        expected = {(r['warehouse_id'], r['country'], r['warehouse_type']) for r in policy['warehouses']}
        self.assertEqual(len(actual), 19)
        self.assertEqual(actual, expected)

    def test_transaction_and_target_uniqueness_precede_writes(self):
        self.assertRegex(self.sql, r'BEGIN TRANSACTION;[\s\S]+ASSERT[\s\S]+MERGE[\s\S]+COMMIT TRANSACTION;')
        self.assertIn('COUNT(DISTINCT warehouse_id)', self.sql)
        self.assertNotRegex(self.sql, r'(?i)DELETE\s+`')
        self.assertNotIn('sp_data_insert_log', self.sql)

    def test_duplicate_target_fails_before_any_changes(self):
        self.add_target()
        self.add_target(name='Duplicate target')
        self.add_source()
        with self.assertRaisesRegex(ValueError, 'unique, nonempty'):
            self.run_refresh()
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM core_warehouse').fetchone()[0], 2)
        self.assertEqual(self.row()['country'], 'VIETNAM')

    def test_repeated_refresh_preserves_one_row_and_display(self):
        self.add_source()
        self.run_refresh()
        before = dict(self.row())
        self.run_refresh()
        self.assertEqual(dict(self.row()), before)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM core_warehouse').fetchone()[0], 1)


if __name__ == '__main__':
    unittest.main()
