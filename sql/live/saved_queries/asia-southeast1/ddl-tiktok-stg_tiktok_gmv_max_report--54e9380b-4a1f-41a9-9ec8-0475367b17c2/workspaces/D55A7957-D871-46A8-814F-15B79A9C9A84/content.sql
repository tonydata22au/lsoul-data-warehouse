--DROP TABLE `marine-cycle-484213-b4.stg_tiktok.stg_tiktok_gmv_max_report`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_tiktok.stg_tiktok_thai_gmv_max_report`
PARTITION BY proc_date
OPTIONS (
  require_partition_filter=false
) AS
SELECT
DATE(TIMESTAMP_TRUNC(_PARTITIONTIME, DAY)) AS proc_date,
SAFE_CAST(stat_time_day AS DATE) AS inserted_at, 
campaign_id, 
campaign_name,
operation_status,
SAFE_CAST(schedule_end_time AS datetime) AS schedule_end_time, 
SAFE_CAST(schedule_start_time AS datetime) AS schedule_start_time, 
schedule_type,
SAFE_CAST(cost AS NUMERIC) AS cost,
SAFE_CAST(cost_per_order AS NUMERIC) AS cost_per_order,
SAFE_CAST(cost_per_10_second_live_view AS NUMERIC) AS cost_per_10_second_live_view,
SAFE_CAST(cost_per_live_view AS NUMERIC) AS cost_per_live_view,
SAFE_CAST(gross_revenue AS NUMERIC) AS gross_revenue,
SAFE_CAST(net_cost AS NUMERIC) AS net_cost,
SAFE_CAST(target_roi_budget AS NUMERIC) AS target_roi_budget,
SAFE_CAST(roi AS NUMERIC) AS roi,
SAFE_CAST(orders AS NUMERIC) AS orders,
SAFE_CAST(roas_bid AS NUMERIC) AS roas_bid,
SAFE_CAST(max_delivery_budget AS NUMERIC) AS max_delivery_budget,
SAFE_CAST(`10_second_live_views` AS NUMERIC) AS `10_second_live_views`,
bid_type,
identity_id,
SAFE_CAST(live_follows AS NUMERIC) AS live_follows,
SAFE_CAST(live_views AS NUMERIC) AS live_views,
tt_account_name 
FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-06-12")


