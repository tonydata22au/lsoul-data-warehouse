-- Raw dataset consolidation: move the 32 raw tables into `marine-cycle-484213-b4.raw`.
-- Plan and protocol: tasks/raw-dataset-plan.md ("Cutover and rollback protocol").
--
-- PREPARED, NOT RUN. Every section needs explicit user authorization (tasks W2-W6) and is run
-- by hand, one section at a time, in a maintenance window outside 07:00-09:00 ICT.
-- Never run the whole file at once. Old tables are kept (never dropped here).
-- This is the only editable SQL allowed to name the old raw datasets
-- (tests/test_raw_dataset_refs.py checks it names exactly these 32 tables).
--
-- Fingerprint of a table t: per ingestion-time partition p (NULL = the __NULL__ partition),
-- n = COUNT(*) and x = BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))). Two tables are equal when
-- every (p, n, x) matches. n is needed because BIT_XOR cancels identical duplicate pairs.
-- The raw tables set require_partition_filter, so each scan carries a filter that still keeps
-- every partition (`_PARTITIONTIME IS NULL OR _PARTITIONTIME >= 1970-01-01`).
-- Table COPY keeps schema, partitioning (_PARTITIONTIME), clustering and data.

-- =============================================================================================
-- Section 0 (W2). Create the dataset. ACLs are mirrored separately (see the plan, decision 6).
-- =============================================================================================
CREATE SCHEMA IF NOT EXISTS `marine-cycle-484213-b4.raw`
OPTIONS (location = 'asia-southeast1',
         description = 'All raw tables written by the LSOUL loaders (append-only, ingestion-time partitioned)');

-- =============================================================================================
-- Section 1 (W3). Freeze check. Run AFTER pausing every writer in the W1 writer set.
-- 1a must return 0 rows. Run 1b, wait at least 10 minutes, run 1c: it must return 0 rows.
-- =============================================================================================

-- 1a. No pending or running job writes to an old raw table.
SELECT job_id, user_email, state, destination_table.dataset_id, destination_table.table_id, creation_time
FROM `region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE state IN ('PENDING', 'RUNNING')
  AND creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
  AND destination_table.dataset_id IN ('raw_pancake', 'raw_tiktok', 'raw_meta', 'dianplus', 'jushuitan', 'magento', 'surfosm')
  AND STARTS_WITH(destination_table.table_id, 'raw_');

-- 1b. Record T_freeze[t] (last_modified_time and row count of every old table).
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.sysdb.raw_cutover_freeze` AS
SELECT *, CURRENT_TIMESTAMP() AS recorded_at FROM (
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_pancake.__TABLES__` WHERE table_id IN ('raw_customer', 'raw_inventory_histories', 'raw_order', 'raw_orders_returned', 'raw_product_variations', 'raw_stats_inventory_variations', 'raw_stats_product')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_tiktok.__TABLES__` WHERE table_id IN ('raw_tiktok_ad_group', 'raw_tiktok_ads', 'raw_tiktok_campaign', 'raw_tiktok_gmv_max_report', 'raw_tiktok_reporting_basic_auction_ad', 'raw_tiktok_reporting_basic_auction_campaign', 'raw_tiktok_thai_ad_group', 'raw_tiktok_thai_ads', 'raw_tiktok_thai_campaign', 'raw_tiktok_thai_gmv_max_report', 'raw_tiktok_thai_reporting_basic_auction_ad')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_meta.__TABLES__` WHERE table_id IN ('raw_ads_reporting_a', 'raw_ads_reporting_ecom', 'raw_ads_reporting_my')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.dianplus.__TABLES__` WHERE table_id IN ('raw_dianplus_inventory', 'raw_dianplus_order', 'raw_dianplus_order_refund', 'raw_dianplus_product')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.jushuitan.__TABLES__` WHERE table_id IN ('raw_jushuitan_inventory', 'raw_jushuitan_order', 'raw_jushuitan_taobao_tmall_order_manual')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.magento.__TABLES__` WHERE table_id IN ('raw_magento_order')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.surfosm.__TABLES__` WHERE table_id IN ('raw_surfosm_inventory', 'raw_surfosm_order', 'raw_surfosm_order_return')
);

-- 1c. Quiescence and the post-copy recheck (also step 3): any row means a write slipped in.
-- Go back to section 1 (re-freeze) and redo section 2.
SELECT f.dataset_id, f.table_id, f.last_modified AS frozen, now.last_modified AS current_value
FROM `marine-cycle-484213-b4.sysdb.raw_cutover_freeze` AS f
JOIN (
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_pancake.__TABLES__` WHERE table_id IN ('raw_customer', 'raw_inventory_histories', 'raw_order', 'raw_orders_returned', 'raw_product_variations', 'raw_stats_inventory_variations', 'raw_stats_product')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_tiktok.__TABLES__` WHERE table_id IN ('raw_tiktok_ad_group', 'raw_tiktok_ads', 'raw_tiktok_campaign', 'raw_tiktok_gmv_max_report', 'raw_tiktok_reporting_basic_auction_ad', 'raw_tiktok_reporting_basic_auction_campaign', 'raw_tiktok_thai_ad_group', 'raw_tiktok_thai_ads', 'raw_tiktok_thai_campaign', 'raw_tiktok_thai_gmv_max_report', 'raw_tiktok_thai_reporting_basic_auction_ad')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.raw_meta.__TABLES__` WHERE table_id IN ('raw_ads_reporting_a', 'raw_ads_reporting_ecom', 'raw_ads_reporting_my')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.dianplus.__TABLES__` WHERE table_id IN ('raw_dianplus_inventory', 'raw_dianplus_order', 'raw_dianplus_order_refund', 'raw_dianplus_product')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.jushuitan.__TABLES__` WHERE table_id IN ('raw_jushuitan_inventory', 'raw_jushuitan_order', 'raw_jushuitan_taobao_tmall_order_manual')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.magento.__TABLES__` WHERE table_id IN ('raw_magento_order')
  UNION ALL
  SELECT dataset_id, table_id, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `marine-cycle-484213-b4.surfosm.__TABLES__` WHERE table_id IN ('raw_surfosm_inventory', 'raw_surfosm_order', 'raw_surfosm_order_return')
) AS now USING (dataset_id, table_id)
WHERE now.last_modified != f.last_modified OR now.row_count != f.row_count;

-- =============================================================================================
-- Section 2 (W4). Final copy of the frozen tables: old -> raw (32 statements).
-- =============================================================================================
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_customer` COPY `marine-cycle-484213-b4.raw_pancake.raw_customer`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_inventory_histories` COPY `marine-cycle-484213-b4.raw_pancake.raw_inventory_histories`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_order` COPY `marine-cycle-484213-b4.raw_pancake.raw_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_orders_returned` COPY `marine-cycle-484213-b4.raw_pancake.raw_orders_returned`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_product_variations` COPY `marine-cycle-484213-b4.raw_pancake.raw_product_variations`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_stats_inventory_variations` COPY `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_stats_product` COPY `marine-cycle-484213-b4.raw_pancake.raw_stats_product`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_ad_group` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ad_group`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_ads` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ads`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_campaign` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_gmv_max_report` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_gmv_max_report`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_ad` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_ad`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_campaign` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_thai_ad_group` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ad_group`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_thai_ads` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ads`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_thai_campaign` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_thai_gmv_max_report` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_tiktok_thai_reporting_basic_auction_ad` COPY `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_ads_reporting_a` COPY `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_a`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_ads_reporting_ecom` COPY `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_ecom`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_ads_reporting_my` COPY `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_my`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_dianplus_inventory` COPY `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_dianplus_order` COPY `marine-cycle-484213-b4.dianplus.raw_dianplus_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_dianplus_order_refund` COPY `marine-cycle-484213-b4.dianplus.raw_dianplus_order_refund`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_dianplus_product` COPY `marine-cycle-484213-b4.dianplus.raw_dianplus_product`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_jushuitan_inventory` COPY `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_jushuitan_order` COPY `marine-cycle-484213-b4.jushuitan.raw_jushuitan_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_jushuitan_taobao_tmall_order_manual` COPY `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_magento_order` COPY `marine-cycle-484213-b4.magento.raw_magento_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_surfosm_inventory` COPY `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_surfosm_order` COPY `marine-cycle-484213-b4.surfosm.raw_surfosm_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw.raw_surfosm_order_return` COPY `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return`;

-- =============================================================================================
-- Section 3 (W4). Verify forward: fingerprint(old) = fingerprint(raw) for all 32 tables.
-- Must return 0 rows (p = 0001-01-01 stands for the __NULL__ partition). Then rerun 1c: 0 rows.
-- On any row: do not deploy; go back to section 1.
-- =============================================================================================
SELECT 'raw_customer' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_customer` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_customer` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_inventory_histories' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_inventory_histories` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_inventory_histories` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_orders_returned' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_orders_returned` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_orders_returned` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_product_variations' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_product_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_stats_inventory_variations' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_stats_inventory_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_stats_product' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_stats_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_stats_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_ad_group' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_ads' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_gmv_max_report' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_reporting_basic_auction_ad' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_reporting_basic_auction_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_ad_group' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_ads' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_gmv_max_report' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_reporting_basic_auction_ad' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_a' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_a` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_a` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_ecom' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_ecom` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_ecom` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_my' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_my` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_my` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_order_refund' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_order_refund` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_order_refund` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_product' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_taobao_tmall_order_manual' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_taobao_tmall_order_manual` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_magento_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.magento.raw_magento_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_magento_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_order_return' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS old_n, b.n AS raw_n, a.x AS old_x, b.x AS raw_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_order_return` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x;

-- =============================================================================================
-- Section 4 (W6). Fence the old raw tables (decision U3, 2026-11-07). The services' old runtime
-- account (266174294882-compute@developer) holds project roles/editor, so dataset or table
-- REVOKEs cannot fence it. Instead every ingestion service is deployed with the dedicated SA
-- lsoul-ingest-runner@marine-cycle-484213-b4.iam.gserviceaccount.com, which holds only:
--   * project roles/bigquery.jobUser
--   * roles/bigquery.dataEditor on dataset `raw` (dataset ACL)
--   * roles/secretmanager.secretAccessor on the secrets its services read
-- and nothing on the old datasets. A stray write to an old raw table then fails with 403.
-- Verify (4a): as the new SA, an append to an old raw table is denied and one to raw succeeds
-- (proven in the rehearsal on scratch datasets). Verify (4b) after resuming: 1c returns 0 rows,
-- that is, no old table changed after T_freeze.
-- =============================================================================================
GRANT `roles/bigquery.dataEditor` ON SCHEMA `marine-cycle-484213-b4.raw`
TO "serviceAccount:lsoul-ingest-runner@marine-cycle-484213-b4.iam.gserviceaccount.com";

-- =============================================================================================
-- Section 5 (rollback only). Reverse reconciliation: raw -> old, BEFORE old readers or writers
-- resume. First pause the writer set again and wait for quiescence on `raw` (1a with dataset
-- 'raw'). Check that the old tables are still frozen (1c returns 0 rows), so raw holds every old
-- row plus rows written only to raw after cutover. Then copy back (32 statements).
-- Note: CREATE OR REPLACE drops table-level IAM on the old tables; re-apply it in rollback step 4.
-- =============================================================================================
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_customer` COPY `marine-cycle-484213-b4.raw.raw_customer`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_inventory_histories` COPY `marine-cycle-484213-b4.raw.raw_inventory_histories`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_order` COPY `marine-cycle-484213-b4.raw.raw_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_orders_returned` COPY `marine-cycle-484213-b4.raw.raw_orders_returned`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_product_variations` COPY `marine-cycle-484213-b4.raw.raw_product_variations`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations` COPY `marine-cycle-484213-b4.raw.raw_stats_inventory_variations`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.raw_stats_product` COPY `marine-cycle-484213-b4.raw.raw_stats_product`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ad_group` COPY `marine-cycle-484213-b4.raw.raw_tiktok_ad_group`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ads` COPY `marine-cycle-484213-b4.raw.raw_tiktok_ads`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_campaign` COPY `marine-cycle-484213-b4.raw.raw_tiktok_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_gmv_max_report` COPY `marine-cycle-484213-b4.raw.raw_tiktok_gmv_max_report`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_ad` COPY `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_ad`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_campaign` COPY `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ad_group` COPY `marine-cycle-484213-b4.raw.raw_tiktok_thai_ad_group`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ads` COPY `marine-cycle-484213-b4.raw.raw_tiktok_thai_ads`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_campaign` COPY `marine-cycle-484213-b4.raw.raw_tiktok_thai_campaign`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report` COPY `marine-cycle-484213-b4.raw.raw_tiktok_thai_gmv_max_report`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad` COPY `marine-cycle-484213-b4.raw.raw_tiktok_thai_reporting_basic_auction_ad`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_a` COPY `marine-cycle-484213-b4.raw.raw_ads_reporting_a`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_ecom` COPY `marine-cycle-484213-b4.raw.raw_ads_reporting_ecom`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_my` COPY `marine-cycle-484213-b4.raw.raw_ads_reporting_my`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory` COPY `marine-cycle-484213-b4.raw.raw_dianplus_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.raw_dianplus_order` COPY `marine-cycle-484213-b4.raw.raw_dianplus_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.raw_dianplus_order_refund` COPY `marine-cycle-484213-b4.raw.raw_dianplus_order_refund`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.raw_dianplus_product` COPY `marine-cycle-484213-b4.raw.raw_dianplus_product`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory` COPY `marine-cycle-484213-b4.raw.raw_jushuitan_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.raw_jushuitan_order` COPY `marine-cycle-484213-b4.raw.raw_jushuitan_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual` COPY `marine-cycle-484213-b4.raw.raw_jushuitan_taobao_tmall_order_manual`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.magento.raw_magento_order` COPY `marine-cycle-484213-b4.raw.raw_magento_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory` COPY `marine-cycle-484213-b4.raw.raw_surfosm_inventory`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.raw_surfosm_order` COPY `marine-cycle-484213-b4.raw.raw_surfosm_order`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return` COPY `marine-cycle-484213-b4.raw.raw_surfosm_order_return`;

-- 5b. Verify rollback: fingerprint(raw) = fingerprint(old) for all 32 tables. Must return 0 rows.
-- Then restore old write access, set BQ_RAW_DATASET to the old dataset (or redeploy the previous
-- revisions), revert the SQL, Dataform (W10) and dbt changes, and resume the writer set.
SELECT 'raw_customer' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_customer` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_customer` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_inventory_histories' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_inventory_histories` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_inventory_histories` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_orders_returned' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_orders_returned` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_orders_returned` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_product_variations' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_product_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_stats_inventory_variations' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_stats_inventory_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_stats_product' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_stats_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_pancake.raw_stats_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_ad_group' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_ads' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_gmv_max_report' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_reporting_basic_auction_ad' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_reporting_basic_auction_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_reporting_basic_auction_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_reporting_basic_auction_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_ad_group' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ad_group` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_ads' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ads` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_campaign' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_campaign` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_gmv_max_report' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_tiktok_thai_reporting_basic_auction_ad' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_tiktok_thai_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_reporting_basic_auction_ad` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_a' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_a` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_a` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_ecom' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_ecom` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_ecom` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_ads_reporting_my' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_ads_reporting_my` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_my` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_order_refund' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_order_refund` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_order_refund` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_dianplus_product' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_dianplus_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_product` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_jushuitan_taobao_tmall_order_manual' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_jushuitan_taobao_tmall_order_manual` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_magento_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_magento_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.magento.raw_magento_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_inventory' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_order' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_order` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x
UNION ALL
SELECT 'raw_surfosm_order_return' AS table_name, IFNULL(a.p, b.p) AS p, a.n AS raw_n, b.n AS old_n, a.x AS raw_x, b.x AS old_x
FROM (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.raw.raw_surfosm_order_return` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS a
FULL OUTER JOIN (SELECT IFNULL(_PARTITIONTIME, TIMESTAMP '0001-01-01') AS p, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS x FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return` AS t WHERE _PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP '1970-01-01' GROUP BY p) AS b
USING (p)
WHERE a.n IS NULL OR b.n IS NULL OR a.n != b.n OR a.x != b.x;
