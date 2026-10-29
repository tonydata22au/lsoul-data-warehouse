-- Synthetic source replacements used by validate_warehouse_monitor.py.
-- No warehouse tables, credentials, or real job records are read by this test.
WITH
inventory_raw AS (
  SELECT 'marine-cycle-484213-b4' AS table_catalog,'raw_pancake' AS table_schema,
    name AS table_name, IF(name='logical_view','VIEW','BASE TABLE') AS table_type,
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 100 DAY) AS creation_time
  FROM UNNEST(['daily_ok','critical','warning','logical_view']) name
),
jobs_raw AS (
  SELECT CONCAT('fixture_',CAST(n AS STRING)) AS job_id,
    IF(n=1,'fixture_parent',NULL) AS parent_job_id,'QUERY' AS job_type,
    IF(n=101,'SELECT','INSERT') AS statement_type,
    TIMESTAMP(DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'),INTERVAL IF(n<15,n,1) DAY),'Asia/Ho_Chi_Minh') AS creation_time,
    TIMESTAMP(DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'),INTERVAL IF(n<15,n,1) DAY),'Asia/Ho_Chi_Minh') AS start_time,
    TIMESTAMP_ADD(TIMESTAMP(DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'),INTERVAL IF(n<15,n,1) DAY),'Asia/Ho_Chi_Minh'),INTERVAL 10 SECOND) AS end_time,
    'DONE' AS state, IF(n=100,'invalidQuery',NULL) AS error_reason,
    STRUCT('marine-cycle-484213-b4' AS project_id,'raw_pancake' AS dataset_id,
      CASE WHEN n=100 THEN 'critical' WHEN n=99 THEN 'warning' ELSE 'daily_ok' END AS table_id) AS destination_table,
    [STRUCT('marine-cycle-484213-b4' AS project_id,'fixture' AS dataset_id,'source1' AS table_id),
     STRUCT('marine-cycle-484213-b4' AS project_id,'fixture' AS dataset_id,'source2' AS table_id)] AS referenced_tables,
    ARRAY<STRUCT<key STRING,value STRING>>[] AS labels,
    'INSERT INTO fixture SELECT 1' AS query,
    1099511627776 AS total_bytes_billed,1000 AS total_slot_ms,
    0 AS total_services_sku_slot_ms,CAST(NULL AS STRING) AS reservation_id,
    FALSE AS cache_hit,1 AS inserted_rows,0 AS updated_rows,'fixture_hash' AS query_hash
  FROM UNNEST(ARRAY_CONCAT(GENERATE_ARRAY(1,14),[99,100,101])) n
  UNION ALL
  SELECT 'fixture_parent',NULL,'QUERY','SCRIPT',TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 1 DAY),
    TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 1 DAY),TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 1 DAY),
    'DONE',NULL,NULL,[],[], 'CALL fixture.proc()',99999999999999,999999,0,NULL,FALSE,NULL,NULL,NULL
),
billing_raw AS (
  SELECT TIMESTAMP(d,'Asia/Ho_Chi_Minh') AS ChargePeriodStart,
    'VND' AS BillingCurrency,NUMERIC '100' AS BilledCost,NUMERIC '80' AS EffectiveCost,
    'VND' AS PricingCurrency,NUMERIC '1000' AS ListUnitPrice,'tebibyte' AS PricingUnit,
    'Analysis (asia-southeast1)' AS ChargeDescription,'asia-southeast1' AS RegionId,
    CURRENT_TIMESTAMP() AS export_time
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'),INTERVAL 58 DAY),
    DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'),INTERVAL 1 DAY))) d
)
