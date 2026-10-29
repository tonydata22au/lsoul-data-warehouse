-- Prepared definition. Deploying this file creates/replaces only this reporting TVF.
-- Grain: one current inventory table per local calendar day, plus UNALLOCATED
-- and PROJECT_BILLING rows. job_details keeps individual jobs without fan-out.
-- End date is inclusive. NULL dates mean the last 30 complete Vietnam days.
CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(
  p_report_type INT64
  , p_service_name STRING
  , p_start_date STRING --20261029
  , p_end_date STRING --20261029
) AS (
WITH
/*
MASTER REPORT: SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations` (0,"bigquery",NULL,NULL) WHERE to_monitor_flag = 1 ORDER BY 1 DESC

JOBs. andlineag: SELECT m.activity_date, IFNULL(m.to_monitor_flag,0) to_monitor_flag, m.table_name, m.table_type, m.original_source_inferred, j.* FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations` (0,"bigquery",NULL,NULL) m, UNNEST(m.job_details) j WHERE to_monitor_flag = 1 ORDER BY 1 DESC 
*/
params AS (
  SELECT
    COALESCE(PARSE_DATE('%Y%m%d', p_start_date), DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 30 DAY)) AS date_from,
    COALESCE(PARSE_DATE('%Y%m%d', p_end_date), CURRENT_DATE('Asia/Ho_Chi_Minh')) AS date_to
),
validated AS (
  SELECT IF(date_from <= date_to AND DATE_DIFF(date_to, date_from, DAY) < 90
      AND date_to <= CURRENT_DATE('Asia/Ho_Chi_Minh')
      AND date_from >= DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 150 DAY),
      date_from, ERROR('Use an ordered date range of 1-90 days, starting within 150 days, ending no later than today.')) AS date_from,
    date_to,
    DATE_DIFF(date_to, date_from, DAY) + 1 AS selected_days,
    --LEAST(date_to, DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY)) AS freshness_as_of
    CURRENT_DATE('Asia/Ho_Chi_Minh') AS freshness_as_of
    
    
  FROM params
),
inventory_raw AS (
SELECT table_catalog, table_schema, table_name, table_type, creation_time,0 AS to_monitor_flag FROM `marine-cycle-484213-b4.analytics_445899027.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,0 AS to_monitor_flag FROM `marine-cycle-484213-b4.analytics_529084033.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.core_meta.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.core_pancake.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.core_tiktok.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.dataform.INFORMATION_SCHEMA.TABLES`
-- UNION ALL
-- SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.dev_core_pancake.INFORMATION_SCHEMA.TABLES`
-- UNION ALL
-- SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.dev_staging.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.dianplus.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.gcp_billing_immutable_01980C_98310B_55822E_asia_southeast1.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,0 AS to_monitor_flag FROM `marine-cycle-484213-b4.google_ads.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.jushuitan.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.magento.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.raw_meta.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.raw_tiktok.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.stg_meta.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.stg_pancake.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.stg_tiktok.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,1 AS to_monitor_flag FROM `marine-cycle-484213-b4.surfosm.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT table_catalog, table_schema, table_name, table_type, creation_time,0 AS to_monitor_flag FROM `marine-cycle-484213-b4.sysdb.INFORMATION_SCHEMA.TABLES`
),
inventory AS (
  SELECT CONCAT(table_catalog, '.', table_schema, '.', table_name) AS table_id,
    table_schema AS dataset_name, table_name AS short_name, table_type,
    creation_time AS table_created_at,
    CASE
      WHEN table_type != 'BASE TABLE' THEN 'NOT_APPLICABLE'
      WHEN REGEXP_CONTAINS(table_name, r'_[0-9]{8}$') THEN 'DATED_SHARD'
      WHEN STARTS_WITH(table_schema, 'gcp_billing_') THEN 'MANAGED_BILLING_EXPORT'
      WHEN STARTS_WITH(table_schema, 'dev_') OR table_schema IN ('dataform', 'sysdb') THEN 'UNSCHEDULED_REVIEW'
      WHEN STARTS_WITH(table_schema, 'analytics_') THEN 'MANAGED_EXPORT_REVIEW'
      ELSE 'DAILY_ASSUMED'
    END AS freshness_policy,
    CASE
      WHEN table_schema LIKE '%pancake%' THEN 'Pancake POS'
      WHEN table_schema LIKE '%meta%' THEN 'Meta Ads'
      WHEN table_schema LIKE '%tiktok%' THEN 'TikTok Ads'
      WHEN table_schema = 'dianplus' THEN 'Dianplus'
      WHEN table_schema = 'jushuitan' THEN 'Jushuitan'
      WHEN table_schema = 'magento' THEN 'Magento'
      WHEN table_schema = 'surfosm' THEN 'Surfosm / ScaleUp'
      WHEN table_schema = 'google_ads' THEN 'Google Ads'
      WHEN STARTS_WITH(table_schema, 'analytics_') THEN 'Google Analytics'
      WHEN STARTS_WITH(table_schema, 'gcp_billing_') THEN 'Google Cloud Billing'
      ELSE 'bq pipeline/dbt'
    END AS original_source_inferred
    ,to_monitor_flag
  FROM inventory_raw
),
-- Weekly Monday 09:15 ICT schedule and table outputs from the 2026-10-28
-- ppl-AI repository snapshot (main/release default). Recheck when schedules change.
weekly_outputs AS (
  SELECT CONCAT('marine-cycle-484213-b4.reportdb.', name) AS table_id
  FROM UNNEST([
    'dash_action_context',
    'dash_action_items',
    'dash_base_ads_day',
    'dash_base_order_day',
    'dash_base_sku_day',
    'dash_base_traffic_day',
    'dash_dq_platform_day',
    'dash_marketing_drivers',
    'dash_material_points',
    'dash_materiality_config',
    'dash_nmv_factor',
    'dash_page1_wow',
    'dash_page2_mtd',
    'dash_page_summary',
    'dash_run_params',
    'dash_stock_lists',
    'dash_target_day',
    'dash_trend_marketing_weekly',
    'dash_trend_monthly',
    'dash_trend_weekly',
    'v_dash_report'
  ]) name
),
jobs_raw AS (
  SELECT job_id, parent_job_id, job_type, statement_type, creation_time,
    start_time, end_time, state, error_result.reason AS error_reason,
    destination_table, referenced_tables, labels, query,
    total_bytes_billed, total_slot_ms, total_services_sku_slot_ms, reservation_id,
    cache_hit, dml_statistics.inserted_row_count AS inserted_rows,
    dml_statistics.updated_row_count AS updated_rows,
    query_info.query_hashes.normalized_literals AS query_hash
  FROM `marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  -- WHERE creation_time >= TIMESTAMP(DATE_SUB((SELECT date_from FROM validated), INTERVAL 29 DAY), 'Asia/Ho_Chi_Minh')
  --   AND creation_time < TIMESTAMP(DATE_ADD((SELECT date_to FROM validated), INTERVAL 1 DAY), 'Asia/Ho_Chi_Minh')
),
jobs_enriched AS (
  SELECT j.* EXCEPT(referenced_tables, labels, query),
    DATE(j.creation_time, 'Asia/Ho_Chi_Minh') AS activity_date,
    CONCAT(j.destination_table.project_id, '.', j.destination_table.dataset_id, '.',
      REGEXP_REPLACE(j.destination_table.table_id, r'\$[0-9]+$', '')) AS destination_id,
    ARRAY_TO_STRING(ARRAY(SELECT DISTINCT CONCAT(r.project_id, '.', r.dataset_id, '.', r.table_id)
      FROM UNNEST(j.referenced_tables) r ORDER BY 1), ', ') AS source_tables,
    CASE WHEN j.state != 'DONE' THEN j.state
      WHEN j.error_reason = 'stopped' THEN 'CANCELLED'
      WHEN j.error_reason IS NOT NULL THEN 'FAILED' ELSE 'SUCCESS' END AS job_status,
    IF(j.end_time IS NOT NULL, TIMESTAMP_DIFF(j.end_time, j.start_time, MILLISECOND)/1000.0, NULL) AS runtime_seconds,
    TIMESTAMP_DIFF(j.start_time, j.creation_time, MILLISECOND)/1000.0 AS queue_seconds,
    COALESCE(
      (SELECT MAX(value) FROM UNNEST(j.labels) WHERE key='dataform_repository_id'),
      (SELECT MAX(value) FROM UNNEST(parent.labels) WHERE key='dataform_repository_id')) AS dataform_repository,
    COALESCE(
      (SELECT MAX(value) FROM UNNEST(j.labels) WHERE key='dts_config_id'),
      (SELECT MAX(value) FROM UNNEST(parent.labels) WHERE key='dts_config_id')) AS transfer_config,
    COALESCE(
      (SELECT MAX(value) FROM UNNEST(j.labels) WHERE key='looker_studio_report_id'),
      (SELECT MAX(value) FROM UNNEST(parent.labels) WHERE key='looker_studio_report_id')) AS looker_report,
    REGEXP_EXTRACT(parent.query, r'(?i)\bCALL\s+`?([\w.\-]+)`?\s*\(') AS procedure_inferred,
    CASE
      WHEN j.job_type IN ('LOAD','COPY') THEN 'UNKNOWN_WRITE_DISPOSITION'
      WHEN j.statement_type = 'INSERT' THEN 'INSERT / incremental candidate'
      WHEN j.statement_type = 'MERGE' THEN 'MERGE / incremental candidate'
      WHEN j.statement_type = 'CREATE_TABLE_AS_SELECT' AND REGEXP_CONTAINS(j.query, r'(?i)\bCREATE\s+OR\s+REPLACE\s+TABLE\b') THEN 'FULL_REBUILD (SQL evidence)'
      WHEN j.statement_type = 'CREATE_TABLE_AS_SELECT' THEN 'CTAS / initial build'
      WHEN j.statement_type IN ('UPDATE','DELETE','TRUNCATE_TABLE') THEN 'MUTATION / not ingestion'
      WHEN j.statement_type = 'CREATE_VIEW' THEN 'VIEW_DEFINITION'
      ELSE 'READ_OR_OTHER'
    END AS load_strategy,
    j.job_type IN ('LOAD','COPY') OR j.statement_type IN ('INSERT','MERGE','CREATE_TABLE_AS_SELECT') AS qualifying_write
  FROM jobs_raw j LEFT JOIN jobs_raw parent ON j.parent_job_id=parent.job_id
  WHERE COALESCE(j.statement_type, '') != 'SCRIPT'
),
-- Actual billing is kept at project/day grain, never replicated over job rows.
billing_raw AS (
  SELECT ChargePeriodStart, BillingCurrency, BilledCost, EffectiveCost,
    PricingCurrency, ListUnitPrice, PricingUnit, ChargeDescription, RegionId,
    x_ExportTime AS export_time
  FROM `marine-cycle-484213-b4.gcp_billing_immutable_01980C_98310B_55822E_asia_southeast1.gcp_billing_export_focus_01980C_98310B_55822E`
  WHERE ChargePeriodStart >= TIMESTAMP(DATE_SUB((SELECT date_from FROM validated), INTERVAL 28 DAY), 'Asia/Ho_Chi_Minh')
    AND ChargePeriodStart < TIMESTAMP(DATE_ADD((SELECT date_to FROM validated), INTERVAL 1 DAY), 'Asia/Ho_Chi_Minh')
    AND x_Project.Id = 'marine-cycle-484213-b4'
    AND (p_service_name is NULL OR LOWER(ServiceName) LIKE '%' || p_service_name || '%')
),
rates AS (
  SELECT DATE(ChargePeriodStart, 'Asia/Ho_Chi_Minh') AS activity_date,
    ARRAY_AGG(STRUCT(ListUnitPrice AS price_per_tib, PricingCurrency AS currency)
      ORDER BY export_time DESC LIMIT 1)[OFFSET(0)] AS rate
  FROM billing_raw
  WHERE PricingUnit='tebibyte' AND ChargeDescription='Analysis (asia-southeast1)'
    AND RegionId='asia-southeast1' AND ListUnitPrice > 0
  GROUP BY 1
),
jobs AS (
  SELECT j.*,
    COALESCE(i.table_id, '(no current inventory destination)') AS table_name,
    i.table_id IS NOT NULL AS has_inventory_destination,
    CASE WHEN dataform_repository IS NOT NULL THEN CONCAT('Dataform: ', dataform_repository)
      WHEN transfer_config IS NOT NULL THEN CONCAT('BigQuery transfer: ', transfer_config)
      WHEN looker_report IS NOT NULL THEN CONCAT('Looker Studio: ', looker_report)
      WHEN procedure_inferred IS NOT NULL THEN CONCAT('Procedure (inferred): ', procedure_inferred)
      WHEN parent_job_id IS NOT NULL THEN 'Script child; caller unknown'
      ELSE 'Unknown; job configuration/audit logs needed' END AS trigger_origin,
    CASE
      WHEN job_type='QUERY' AND cache_hit THEN 0.0
      WHEN job_type='QUERY' AND reservation_id IS NULL AND total_bytes_billed IS NOT NULL
        AND COALESCE(total_services_sku_slot_ms,0)=0
        AND COALESCE(statement_type,'') NOT IN ('CREATE_MODEL','CALL')
        THEN total_bytes_billed / POW(1024,4) * rate.price_per_tib
      ELSE NULL END AS estimated_query_cost,
    rate.currency AS estimate_currency,
    CASE WHEN job_type != 'QUERY' THEN 'NON_QUERY_COST_NOT_ALLOCATED'
      WHEN reservation_id IS NOT NULL THEN 'CAPACITY_COST_NOT_ALLOCATED'
      WHEN total_bytes_billed IS NULL THEN 'BYTES_UNAVAILABLE'
      WHEN COALESCE(total_services_sku_slot_ms,0)>0 OR statement_type IN ('CREATE_MODEL','CALL') THEN 'SPECIAL_PRICING_NOT_ALLOCATED'
      WHEN cache_hit THEN 'CACHE_HIT_ZERO_QUERY_COST'
      WHEN rate.price_per_tib IS NULL THEN 'DAILY_PRICE_UNAVAILABLE'
      ELSE 'GROSS_ON_DEMAND_ESTIMATE_EXCLUDES_CREDITS' END AS cost_basis
  FROM jobs_enriched j
  LEFT JOIN inventory i ON j.destination_id=i.table_id
  LEFT JOIN rates USING(activity_date)
),
daily AS (
  SELECT table_name, activity_date,
    COUNT(*) AS job_count, COUNTIF(job_status='SUCCESS') AS success_count,
    COUNTIF(job_status='FAILED') AS failed_count, COUNTIF(job_status='CANCELLED') AS cancelled_count,
    COUNTIF(job_status='RUNNING') AS running_count, COUNTIF(job_status='PENDING') AS pending_count,
    COUNT(runtime_seconds) AS completed_runtime_count, SUM(runtime_seconds) AS total_runtime_seconds,
    SUM(total_slot_ms)/1000.0 AS slot_seconds,
    SUM(estimated_query_cost) AS estimated_query_cost,
    COUNTIF(job_type='QUERY' AND estimated_query_cost IS NULL) AS unpriced_query_count,
    STRING_AGG(DISTINCT estimate_currency, ', ') AS estimate_currency,
    STRING_AGG(DISTINCT NULLIF(source_tables,''), ' | ' LIMIT 20) AS source_tables,
    STRING_AGG(DISTINCT trigger_origin, ' | ' LIMIT 10) AS trigger_origin,
    STRING_AGG(DISTINCT load_strategy, ' | ' LIMIT 10) AS load_strategy,
    ARRAY_AGG(STRUCT(job_id, parent_job_id, job_type, statement_type, job_status, error_reason,
      creation_time, start_time, end_time, runtime_seconds, queue_seconds, destination_id,
      source_tables, trigger_origin, procedure_inferred, load_strategy, qualifying_write,
      inserted_rows, updated_rows, estimated_query_cost, estimate_currency, cost_basis)
      ORDER BY creation_time) AS job_details
  FROM jobs GROUP BY 1,2
),
health_stats AS (
  SELECT table_name,
    MAX(IF(qualifying_write, COALESCE(end_time,start_time,creation_time), NULL)) AS last_write_attempt_end,
    MAX(IF(qualifying_write AND job_status='SUCCESS', end_time, NULL)) AS last_successful_write_end,
    COUNT(DISTINCT IF(qualifying_write AND job_status='SUCCESS'
      AND DATE(end_time,'Asia/Ho_Chi_Minh') BETWEEN DATE_SUB(v.freshness_as_of, INTERVAL 13 DAY) AND v.freshness_as_of,
      DATE(end_time,'Asia/Ho_Chi_Minh'), NULL)) AS successful_write_days_14,
    COUNT(DISTINCT IF(qualifying_write
      AND DATE(creation_time,'Asia/Ho_Chi_Minh') BETWEEN DATE_SUB(v.freshness_as_of, INTERVAL 13 DAY) AND v.freshness_as_of,
      DATE(creation_time,'Asia/Ho_Chi_Minh'), NULL)) AS attempted_write_days_14
  FROM jobs CROSS JOIN validated v
  WHERE end_time < TIMESTAMP(DATE_ADD(v.freshness_as_of,INTERVAL 1 DAY),'Asia/Ho_Chi_Minh') OR end_time IS NULL
  GROUP BY 1
),
health AS (
  SELECT i.*, h.* EXCEPT(table_name),
    CASE
      WHEN freshness_policy='NOT_APPLICABLE' THEN CONCAT('N/A: ', table_type)
      WHEN freshness_policy!='DAILY_ASSUMED' THEN CONCAT('REVIEW: ',freshness_policy)
      WHEN table_created_at > TIMESTAMP(DATE_SUB(v.freshness_as_of,INTERVAL 13 DAY),'Asia/Ho_Chi_Minh') THEN 'NEW: under 14 complete days'
      WHEN COALESCE(successful_write_days_14,0)=0 THEN 'CRITICAL'
      WHEN EXISTS(SELECT 1 FROM weekly_outputs w WHERE w.table_id=i.table_id) THEN
        IF(DATE(last_successful_write_end,'Asia/Ho_Chi_Minh')<DATE_SUB(v.freshness_as_of,INTERVAL 7 DAY),'WARNING: weekly overdue','OK: weekly cadence')
      WHEN successful_write_days_14<=6 THEN 'WARNING'
      ELSE 'OK' END AS freshness_status
  FROM inventory i LEFT JOIN health_stats h ON i.table_id=h.table_name CROSS JOIN validated v
),
entities AS (
  SELECT table_id AS table_name,short_name, table_type, original_source_inferred, freshness_status,
    IF(EXISTS(SELECT 1 FROM weekly_outputs w WHERE w.table_id=health.table_id),'WEEKLY_MONDAY_0915_ICT',freshness_policy) AS freshness_policy, last_write_attempt_end, last_successful_write_end,
    COALESCE(successful_write_days_14,0) AS successful_write_days_14,
    COALESCE(attempted_write_days_14,0) AS attempted_write_days_14
  FROM health
  UNION ALL
  SELECT '(no current inventory destination)',null, 'UNALLOCATED', 'Unknown / multiple', 'N/A', 'N/A',
    NULL,NULL,NULL,NULL
),
calendar AS (
  SELECT d AS activity_date FROM validated,
    UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(date_from,INTERVAL 28 DAY), date_to)) d
),
series AS (
  SELECT e.*, c.activity_date, d.* EXCEPT(table_name,activity_date),
    COALESCE(d.job_count,0) AS jobs_including_zero,
    COALESCE(d.total_runtime_seconds,0) AS runtime_including_zero
  FROM entities e CROSS JOIN calendar c LEFT JOIN daily d USING(table_name,activity_date)
),
-- Compare each day with the same weekday in the preceding four weeks.
-- Calendar zeroes count, but a table created later is marked insufficient below.
baseline AS (
  SELECT s.*,
    COUNT(*) OVER w AS baseline_days,
    AVG(jobs_including_zero) OVER w AS baseline_jobs,
    STDDEV_POP(jobs_including_zero) OVER w AS sd_jobs,
    AVG(runtime_including_zero) OVER w AS baseline_runtime,
    STDDEV_POP(runtime_including_zero) OVER w AS sd_runtime,
    COUNT(estimated_query_cost) OVER w AS priced_baseline_days,
    AVG(estimated_query_cost) OVER w AS baseline_estimated_cost,
    STDDEV_POP(estimated_query_cost) OVER w AS sd_estimated_cost
  FROM series s
  WINDOW w AS (PARTITION BY table_name, EXTRACT(DAYOFWEEK FROM activity_date)
    ORDER BY UNIX_DATE(activity_date) RANGE BETWEEN 28 PRECEDING AND 1 PRECEDING)
),
output AS (
  SELECT 
    b.activity_date,
    IF(b.table_type='UNALLOCATED','UNALLOCATED','TABLE_DAY') AS record_type,
    IFNULL(to_monitor_flag,0) AS to_monitor_flag,
    b.table_name, b.short_name, b.table_type, b.original_source_inferred,
    'INFERRED from dataset naming; see docs/pipelines.md' AS source_evidence,
    b.source_tables, b.trigger_origin, b.load_strategy,
    b.freshness_status, b.freshness_policy, b.last_write_attempt_end, b.last_successful_write_end,
    b.successful_write_days_14, 14-b.successful_write_days_14 AS missing_write_days_14,
    b.attempted_write_days_14, v.freshness_as_of,
    b.jobs_including_zero AS job_count,
    COALESCE(b.success_count,0) AS success_count, COALESCE(b.failed_count,0) AS failed_count,
    COALESCE(b.cancelled_count,0) AS cancelled_count, COALESCE(b.running_count,0) AS running_count,
    COALESCE(b.pending_count,0) AS pending_count,
    b.runtime_including_zero AS total_runtime_seconds,
    COALESCE(b.completed_runtime_count,0) AS completed_runtime_count,
    b.slot_seconds,
    IF(b.job_count>0 AND b.table_type!='UNALLOCATED',b.table_name,NULL) AS table_with_jobs,
    IF(b.success_count>0 AND b.table_type!='UNALLOCATED',b.table_name,NULL) AS table_with_success,
    b.runtime_including_zero/v.selected_days AS runtime_seconds_per_selected_day,
    b.estimated_query_cost, b.estimated_query_cost/v.selected_days AS estimated_cost_per_selected_day,
    COALESCE(b.unpriced_query_count,0) AS unpriced_query_count,
    b.estimate_currency AS currency,
    CAST(NULL AS NUMERIC) AS billed_cost, CAST(NULL AS NUMERIC) AS effective_cost,
    CAST(NULL AS FLOAT64) AS billed_cost_per_selected_day,
    CAST(NULL AS TIMESTAMP) AS billing_last_export,
    CASE
      WHEN b.failed_count>0 THEN 'FAILED_JOBS'
      WHEN b.baseline_days<4 OR DATE(i.table_created_at,'Asia/Ho_Chi_Minh')>DATE_SUB(b.activity_date,INTERVAL 28 DAY) THEN 'INSUFFICIENT_HISTORY'
      WHEN b.runtime_including_zero>GREATEST(2*b.baseline_runtime,b.baseline_runtime+3*b.sd_runtime,60) THEN 'RUNTIME_SPIKE'
      WHEN b.jobs_including_zero>GREATEST(2*b.baseline_jobs,b.baseline_jobs+3*b.sd_jobs,10) THEN 'JOB_VOLUME_SPIKE'
      WHEN b.baseline_jobs>=10 AND b.jobs_including_zero<0.5*b.baseline_jobs THEN 'JOB_VOLUME_DROP'
      ELSE 'NO_RULE_TRIGGERED' END AS anomaly_status,
    b.baseline_days, b.baseline_jobs, b.baseline_runtime,
    CASE WHEN b.unpriced_query_count>0 OR b.estimated_query_cost IS NULL OR b.priced_baseline_days<4 THEN 'INSUFFICIENT_PRICED_HISTORY'
      WHEN b.estimated_query_cost>GREATEST(2*b.baseline_estimated_cost,b.baseline_estimated_cost+3*b.sd_estimated_cost) AND b.estimated_query_cost>0 THEN 'ESTIMATED_COST_SPIKE'
      ELSE 'NO_RULE_TRIGGERED' END AS cost_anomaly_status,
    b.baseline_estimated_cost,
    v.selected_days, b.job_details
  FROM baseline b CROSS JOIN validated v LEFT JOIN inventory i ON b.table_name=i.table_id
  WHERE b.activity_date BETWEEN v.date_from AND v.date_to
),
billing_daily AS (
  SELECT DATE(ChargePeriodStart,'Asia/Ho_Chi_Minh') AS activity_date, BillingCurrency AS currency,
    SUM(BilledCost) AS billed_cost, SUM(EffectiveCost) AS effective_cost, MAX(export_time) AS billing_last_export
  FROM billing_raw CROSS JOIN validated v
  WHERE DATE(ChargePeriodStart,'Asia/Ho_Chi_Minh') BETWEEN v.date_from AND v.date_to
  GROUP BY 1,2
),
master_report AS (
SELECT * FROM output 
FULL OUTER UNION ALL BY NAME
SELECT activity_date,
  'PROJECT_BILLING' AS record_type, 
  0 AS to_monitor_flag,
  '(project billing; unallocated to tables)' AS table_name,
  'google_cloud_billing' AS short_name,
  'BASE TABLE' AS table_type,
  'GCP Billing' AS original_source_inferred,
  currency, billed_cost, effective_cost,
  CAST(billed_cost AS FLOAT64)/selected_days AS billed_cost_per_selected_day,
  billing_last_export, selected_days
FROM billing_daily CROSS JOIN validated
)
SELECT *  FROM master_report WHERE p_report_type = 0 --warehouse_operations
FULL OUTER UNION ALL BY NAME
SELECT m.activity_date, IFNULL(m.to_monitor_flag,0) to_monitor_flag, m.table_name, m.table_type, m.original_source_inferred, j.* FROM master_report m, UNNEST(m.job_details) j WHERE p_report_type = 1 --Jobs. andlineage

);
