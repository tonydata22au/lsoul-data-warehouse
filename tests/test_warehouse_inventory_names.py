"""Canonical names at inventory/report grain; execute extracted SQL offline.

SQLite exercises the actual lookup predicates, projections and selected CTEs. It
is not a substitute for GoogleSQL compilation of the complete proposed graph.
"""
from contextlib import closing
from pathlib import Path
import hashlib
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'sql/functions'
SNAPSHOT = ROOT / 'sql/live/bigquery/reportdb/routines'
CHINA = '76be7836-6dc5-4b1c-9e48-b18e43127453'
THAI = '878504e9-fb75-4870-8504-b2ecdbc097ba'
NAMES = (
    'fn_china_product_inventory', 'fn_thailand_product_inventory',
    'fn_product_variations_warehouse_summary', 'fn_product_inventory_overseas_shipment',
    'fn_assortment_seg_cont_by_warehouse', 'fn_stats_product_v2',
    'fn_product_inventory_summary', 'fn_product_inventory_summary_v2',
)


def source(name):
    for path in (BASE / ('reportdb.' + name + '.sql'), SNAPSHOT / (name + '.sql')):
        if path.exists():
            return path.read_text()
    raise AssertionError('Missing source: ' + name)


def executable(sql):
    return re.sub(r'--[^\n]*', '', re.sub(r'/\*.*?\*/', '', sql, flags=re.S))


def cte(sql, name):
    """Read balanced CTE body; fixture SQL has no literal parentheses."""
    start = re.search(r'\b' + name + r'\s+AS\s*\(', sql, re.I).end()
    depth = 1
    for end in range(start, len(sql)):
        depth += (sql[end] == '(') - (sql[end] == ')')
        if depth == 0:
            return sql[start:end]
    raise AssertionError('Unclosed CTE ' + name)


def lookup(sql):
    match = re.search(
        r'LEFT JOIN\s*\(\s*SELECT warehouse_id AS canonical_warehouse_id,\s*'
        r'warehouse_name AS canonical_warehouse_name\s+FROM\s+'
        r'`marine-cycle-484213-b4\.core\.core_pancake__warehouse`\s*\) cw\s*'
        r'ON cw\.canonical_warehouse_id = ([^\n]+)', executable(sql), re.I)
    if not match:
        raise AssertionError('Missing canonical dimension lookup')
    return match.group(1).strip().rstrip(';')


def evaluate_lookup(sql, fixture, alias, values):
    key = lookup(sql)
    with closing(sqlite3.connect(':memory:')) as db:
        db.execute('CREATE TABLE core_warehouse(warehouse_id TEXT PRIMARY KEY, warehouse_name TEXT)')
        db.executemany('INSERT INTO core_warehouse VALUES (?,?)', [
            (CHINA, 'Current China'), (THAI, 'Current Thailand'), ('item', 'Current item'),
            ('reused-name', 'Historical name'), ('null-name', None)])
        columns = ','.join(fixture)
        query = (f'WITH {alias}({columns}) AS (VALUES ({",".join("?" for _ in fixture)})) '
                 'SELECT cw.canonical_warehouse_name FROM ' + alias + ' LEFT JOIN '
                 '(SELECT warehouse_id AS canonical_warehouse_id, '
                 'warehouse_name AS canonical_warehouse_name FROM core_warehouse) cw '
                 f'ON cw.canonical_warehouse_id = {key}')
        return db.execute(query, values).fetchall()


class InventorySourceNameTests(unittest.TestCase):
    def test_fixed_overseas_reporting_ids_resolve_current_names(self):
        for name, key, expected in [
            ('fn_china_product_inventory', CHINA, 'Current China'),
            ('fn_thailand_product_inventory', THAI, 'Current Thailand'),
        ]:
            sql = source(name)
            with self.subTest(function=name):
                self.assertEqual(lookup(sql), repr(key))
                self.assertEqual(evaluate_lookup(sql, ['warehouse_name'], 'i', ['Historical name']), [(expected,)])
                self.assertIn('cw.canonical_warehouse_name AS warehouse_name', sql)
                if key == CHINA:
                    self.assertEqual(sql.count('cw.canonical_warehouse_name AS warehouse_name'), 2)

    def test_dianplus_stock_delta_keeps_source_warehouse_partitions(self):
        sql = executable(source('fn_china_product_inventory'))
        expression = re.search(r'IFNULL\(realNum - LAG\(realNum\).*?AS sl_nhap_kho', sql, re.S).group(0)
        self.assertIn('i.source_warehouse_name', expression)
        with closing(sqlite3.connect(':memory:')) as db:
            db.execute('CREATE TABLE i(skuId, source_warehouse_name, updated_at, realNum)')
            db.executemany('INSERT INTO i VALUES (?,?,?,?)', [
                ('sku','store-A',1,10), ('sku','store-B',2,100),
                ('sku','store-A',3,14), ('sku','store-B',4,97)])
            rows = db.execute('SELECT ' + expression + ' FROM i ORDER BY updated_at').fetchall()
            self.assertEqual(rows, [(0,), (0,), (4,), (-3,)])

    def test_variation_names_are_canonical_before_daily_grouping(self):
        sql = source('fn_product_variations_warehouse_summary')
        self.assertIn('cw.canonical_warehouse_name AS inv_warehouse_name', sql)
        self.assertEqual(lookup(sql), 'i.inv_warehouse_id')
        body = cte(executable(sql), 'stats_variations_by_warehouse_insertedat')
        with closing(sqlite3.connect(':memory:')) as db:
            db.execute('CREATE TABLE stats_variations_by_warehouse(inserted_at,product_code,variation_display_id,variation_name,product_launch_date,inv_warehouse_id,inv_warehouse_name,retail_price,stock_in_qty,sort_num,stock_total_current_qty_by_warehouse,new_stock_in_qty,stock_total_current_qty_all_warehouses)')
            db.executemany('INSERT INTO stats_variations_by_warehouse VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)', [
                ('2026-11-02','p','sku','v','2026-01-01','item','Current item',100,3,2,10,3,20),
                ('2026-11-02','p','sku','v','2026-01-01','item','Current item',100,4,1,14,4,24)])
            rows = db.execute(body).fetchall()
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][8:], (7,14,7,24))


class ReportConsumerNameTests(unittest.TestCase):
    def test_shipment_display_follows_item_but_filters_follow_header(self):
        sql = source('fn_product_inventory_overseas_shipment')
        self.assertEqual(lookup(sql), 'oi.warehouse_id')
        self.assertIn('cw.canonical_warehouse_name AS warehouse_name', sql)
        for key, expected in [('item', 'Current item'), ('missing', None), ('', None), (None, None), ('null-name', None)]:
            with self.subTest(key=key):
                self.assertEqual(evaluate_lookup(sql, ['warehouse_id','warehouse_name'], 'oi', [key,'Historical name']), [(expected,)])
        self.assertIn("AND o.warehouse_id IN ('" + THAI + "','" + CHINA + "')", sql)

    def test_persisted_stats_resolve_names_and_preserve_only_summary_blanks(self):
        sql = executable(source('fn_stats_product_v2'))
        self.assertEqual(lookup(sql), 'alerted.warehouse_id')
        expression = re.search(r"CASE WHEN i_type = 1 AND warehouse_id = '' THEN '' ELSE cw.canonical_warehouse_name END", sql)
        self.assertIsNotNone(expression)
        with closing(sqlite3.connect(':memory:')) as db:
            query = ('WITH alerted(warehouse_id) AS (VALUES (?)), '
                     'cw(canonical_warehouse_name) AS (VALUES (?)) '
                     'SELECT ' + expression.group(0).replace('i_type', '?') + ' FROM alerted CROSS JOIN cw')
            for key, canonical, mode, expected in [('item','Current',0,'Current'), ('item','Current',1,'Current'), ('',None,1,''), ('',None,0,None), (None,None,1,None)]:
                self.assertEqual(db.execute(query,(key,canonical,mode)).fetchone()[0], expected)

    def test_assortment_keeps_distinct_ids_even_when_names_match(self):
        sql = executable(source('fn_assortment_seg_cont_by_warehouse')).split('\nAS\n',1)[1].rstrip(';\n')
        self.assertEqual(lookup(sql), 'sp.warehouse_id')
        sql = re.sub(r'`marine-cycle-484213-b4\.[^.]+\.([^`]+)`', r'\1', sql)
        sql = sql.replace('SAFE_CAST','CAST').replace('i_exclude_sale_end', '0').replace('i_type', '0')
        with closing(sqlite3.connect(':memory:')) as db:
            db.create_function('SAFE_DIVIDE',2,lambda a,b: a/b if b else None)
            db.executescript("""
                CREATE TABLE core_pancake__warehouse(warehouse_id TEXT PRIMARY KEY, warehouse_name TEXT);
                CREATE TABLE report_order_product_inventory_summary(d_date,variation_code,retail_price,warehouse_id,warehouse_name,is_latest,sl_ton_kho,revenue,units_sold,units_sold_day_range,report_type);
                CREATE TABLE product_tree_csv(string_field_1,string_field_2,string_field_3,string_field_4,string_field_5,string_field_6);
                INSERT INTO core_pancake__warehouse VALUES ('A','Shared canonical name'),('B','Shared canonical name');
                INSERT INTO product_tree_csv VALUES ('sku',100,'segment','group','collection',NULL);
                INSERT INTO report_order_product_inventory_summary VALUES ('2026-11-02','sku',100,'A','Old A',1,10,100,1,1,0),('2026-11-02','sku',100,'B','Old B',1,20,200,2,2,0);
            """)
            rows = db.execute(sql).fetchall()
            self.assertEqual(len(rows),2)
            self.assertEqual({row[2] for row in rows},{'Shared canonical name'})
            self.assertEqual(sorted(row[3] for row in rows),[10,20])
            self.assertEqual(sum(row[8] for row in rows),300)


class InventorySummaryNameTests(unittest.TestCase):
    def test_summary_names_ignore_old_labels_and_cutover_dates(self):
        for name, section in [('fn_product_inventory_summary','cte_02'), ('fn_product_inventory_summary_v2','src_filtered')]:
            with self.subTest(function=name):
                sql = executable(source(name))
                body = cte(sql,section)
                self.assertIn('cw.canonical_warehouse_name AS warehouse_name', body)
                self.assertEqual(lookup(body), 's.warehouse_id')
                self.assertNotIn('wh_china_label',body)
                if section == 'cte_02':
                    # Execute this entire transformation using a synthetic source
                    # stream instead of the four underlying table functions.
                    start = body.index('FROM\n  (')
                    end = body.index(') s',start)
                    body = body[:start] + 'FROM source_stream s' + body[end+3:]
                    body = body.replace('LEFT(variation_code,2)', 'SUBSTR(variation_code,1,2)')
                else:
                    body = body.replace('src_union s','source_stream s')
                    body = body.replace('NOT IN UNNEST(c.excluded_sku_prefixes)', "NOT IN ('TG','HT','HN','HH','TD')")
                body = body.replace('`marine-cycle-484213-b4.core.core_pancake__warehouse`','core_warehouse')
                with closing(sqlite3.connect(':memory:')) as db:
                    db.executescript("""
                        CREATE TABLE core_warehouse(warehouse_id TEXT PRIMARY KEY, warehouse_name TEXT);
                        CREATE TABLE source_stream(period_date,src_priority,variation_code,product_name,retail_price,warehouse_id,warehouse_name,sl_nhap_moi_tu_sx,sl_nhap_kho,sl_ton_kho,stock_level_raw,order_sources_name,sale_channel,sale_channel_details,order_year,sales_revenue,revenue,units_sold);
                        CREATE TABLE const(unused); INSERT INTO const VALUES (1);
                    """)
                    db.execute('INSERT INTO core_warehouse VALUES (?,?)',(CHINA,'Current China'))
                    db.executemany('INSERT INTO source_stream VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
                        ('2026-05-31',1,'sku','Product',100,CHINA,'Old China',2,2,5,5,None,None,None,2026,0,0,0),
                        ('2026-06-01',1,'sku','Product',100,CHINA,'Combined legacy label',2,2,2,2,None,None,None,2026,100,90,1),
                        ('2026-06-02',1,'sku','Product',100,'missing','Old China',0,0,3,3,None,None,None,2026,20,18,1)])
                    first = db.execute(body).fetchall()
                    names = [col[0] for col in db.execute(body).description]
                    display_index = names.index('warehouse_name')
                    self.assertEqual([row[display_index] for row in first], ['Current China','Current China',None])
                    stock_index = names.index('sl_ton_kho' if section == 'cte_02' else 'stock_level_raw')
                    self.assertEqual([row[stock_index] for row in first], [5,7,3])
                    db.execute("UPDATE source_stream SET warehouse_name = 'Another unrelated label'")
                    self.assertEqual(db.execute(body).fetchall(),first)
                    db.execute("UPDATE core_warehouse SET warehouse_name = 'Future China'")
                    renamed = db.execute(body).fetchall()
                    self.assertEqual([r[:display_index]+r[display_index+1:] for r in renamed],
                                     [r[:display_index]+r[display_index+1:] for r in first])

    def test_richer_local_v2_source_is_archived_without_loss(self):
        archive = ROOT / 'sql/archive/zarchived-fn_product_inventory_summary_v2-pre-canonical-20261102.sql'
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(),
                         'a725ac9f3b1c85983b094f13d04ddfa373a29c7caf17432c9db70254688f05e7')

    def test_aggregate_modes_keep_blank_names(self):
        old = source('fn_product_inventory_summary')
        self.assertIn("'' AS warehouse_name", cte(old,'cte_07_type1'))
        sql = source('fn_product_inventory_summary_v2')
        expr = re.search(r"IF\(i_type = 1, '', ANY_VALUE\(warehouse_name\)\)", cte(sql,'grain')).group(0)
        expr = expr.replace('ANY_VALUE','MAX').replace('i_type','?')
        with closing(sqlite3.connect(':memory:')) as db:
            db.create_function('IF',3,lambda c,y,n:y if c else n)
            query = "WITH t(warehouse_name) AS (VALUES ('Current')) SELECT " + expr + ' FROM t'
            self.assertEqual(db.execute(query,(1,)).fetchone()[0],'')
            self.assertEqual(db.execute(query,(0,)).fetchone()[0],'Current')


if __name__ == '__main__':
    unittest.main()
