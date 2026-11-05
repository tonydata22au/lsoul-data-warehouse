import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import sql_index  # noqa: E402


class SqlIndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for layer in sql_index.LAYERS:
            (self.root / 'sql' / layer).mkdir(parents=True)
        (self.root / 'sql/live/bigquery/reportdb/routines').mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_targets_cover_create_dataform_and_insert(self):
        self.assertEqual(sql_index.targets(
            '-- create table `p.x.old` as\nCREATE OR REPLACE TABLE FUNCTION `p.reportdb.fn_a`() AS (select 1)'),
            ['reportdb.fn_a'])
        self.assertEqual(sql_index.targets('config {\n  name:"stg_order",\n  dataset:"stg_pancake",\n}\nselect 1'),
                         ['stg_pancake.stg_order'])
        self.assertEqual(sql_index.targets('INSERT INTO `p.core_pancake.core_x` select 1'), ['core_pancake.core_x'])

    def test_status_ignores_comments_case_quoting_and_or_replace(self):
        self.write('sql/live/bigquery/reportdb/routines/fn_a.sql',
                   'CREATE TABLE FUNCTION `p`.reportdb.fn_a() AS (SELECT 1)')
        self.write('sql/functions/reportdb.fn_a.sql',
                   '/* header */\ncreate or replace table function `p.reportdb.fn_a`()\nas (select 1) -- note')
        self.write('sql/functions/reportdb.fn_b.sql', 'create table function `p.reportdb.fn_b`() as (select 2)')
        status = {r['object']: r['status'] for r in sql_index.index(self.root)}
        self.assertEqual(status, {'reportdb.fn_a': 'same', 'reportdb.fn_b': 'not deployed'})

    def test_check_flags_misnamed_nested_and_duplicate_files(self):
        self.write('sql/functions/fn_a.sql', 'create table function `p.reportdb.fn_a`() as (select 1)')
        self.write('sql/functions/sub/reportdb.fn_a.sql', 'create table function `p.reportdb.fn_a`() as (select 1)')
        errors = sql_index.check(self.root)
        self.assertTrue(any('rename it to reportdb.fn_a.sql' in e for e in errors), errors)
        self.assertTrue(any('nested folder' in e for e in errors), errors)
        self.assertTrue(any('more than one editable file' in e for e in errors), errors)

    def test_repository_layout_is_clean(self):
        self.assertEqual(sql_index.check(), [])


if __name__ == '__main__':
    unittest.main()
