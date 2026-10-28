CREATE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_gmv_max_report`
(
  stat_time_day STRING,
  campaign_id STRING,
  campaign_name STRING,
  operation_status STRING,
  schedule_end_time STRING,
  schedule_start_time STRING,
  schedule_type STRING,
  cost STRING,
  cost_per_order STRING,
  cost_per_10_second_live_view STRING,
  cost_per_live_view STRING,
  gross_revenue STRING,
  net_cost STRING,
  target_roi_budget STRING,
  roi STRING,
  orders STRING,
  roas_bid STRING,
  max_delivery_budget STRING,
  `10_second_live_views` STRING,
  bid_type STRING,
  identity_id STRING,
  live_follows STRING,
  live_views STRING,
  tt_account_name STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
