-- SELECT examples AFTER the reporting TVF has been deployed.
-- Pass explicit inclusive local dates, or NULL,NULL for the last 30 complete days.
-- 1. KPI cards
SELECT COUNT(DISTINCT table_with_jobs) AS tables_with_jobs,
  COUNT(DISTINCT table_with_success) AS tables_with_success,
  SUM(runtime_seconds_per_selected_day)/3600 AS avg_execution_hours_per_day,
  SUM(billed_cost_per_selected_day) AS avg_project_billed_cost_per_day
FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(NULL,NULL);

-- 2. Daily outcomes and runtime
SELECT activity_date, SUM(job_count) AS jobs, SUM(success_count) AS successes,
  SUM(failed_count) AS failures, SUM(cancelled_count) AS cancelled,
  SUM(running_count) AS running, SUM(pending_count) AS pending,
  SUM(total_runtime_seconds) AS total_runtime_seconds,
  SAFE_DIVIDE(SUM(total_runtime_seconds),SUM(completed_runtime_count)) AS mean_job_seconds
FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(NULL,NULL)
WHERE record_type!='PROJECT_BILLING'
GROUP BY 1 ORDER BY 1;

-- 3. Actual daily project spend; do not apply a table-name filter.
SELECT activity_date,currency,billed_cost,effective_cost,billing_last_export
FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(NULL,NULL)
WHERE record_type='PROJECT_BILLING' ORDER BY 1;

-- 4. Freshness and anomaly investigation
SELECT table_name,table_type,freshness_status,MAX(last_successful_write_end) AS last_success,
  MAX(missing_write_days_14) AS missing_days,SUM(failed_count) AS failed_jobs,
  COUNTIF(anomaly_status IN ('RUNTIME_SPIKE','JOB_VOLUME_SPIKE','JOB_VOLUME_DROP')) AS anomaly_table_days,
  COUNTIF(cost_anomaly_status='ESTIMATED_COST_SPIKE') AS cost_spike_days,
  SUM(estimated_query_cost) AS estimated_query_cost, SUM(unpriced_query_count) AS unpriced_queries
FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(NULL,NULL)
WHERE record_type='TABLE_DAY'
GROUP BY 1,2,3 ORDER BY failed_jobs DESC, missing_days DESC;

-- 5. Individual job details. No daily metrics are summed after UNNEST.
SELECT m.table_name,m.table_type,m.original_source_inferred,j.*
FROM `marine-cycle-484213-b4.reportdb.fn_warehouse_operations`(NULL,NULL) m,
  UNNEST(m.job_details) j ORDER BY j.creation_time DESC;
