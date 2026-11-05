--DROP TABLE `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report`
PARTITION BY inserted_at
CLUSTER BY  campaign_id
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
inserted_at,
campaign_id,
campaign_name,
operation_status,
schedule_start_time,
schedule_end_time,
schedule_type,
bid_type,
identity_id,
tt_account_name,
cost,
cost_per_order,
cost_per_10_second_live_view,
cost_per_live_view,
max_delivery_budget,
target_roi_budget,
roi,
roas_bid,
orders,
gross_revenue,
net_cost,
live_follows,
live_views,
`10_second_live_views`
FROM `marine-cycle-484213-b4.stg_tiktok.stg_tiktok_gmv_max_report`
WHERE proc_date >= '2026-06-12'