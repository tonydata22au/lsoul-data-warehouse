CREATE TABLE `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report`
(
  inserted_at DATE,
  campaign_id STRING,
  campaign_name STRING,
  operation_status STRING,
  schedule_start_time DATETIME,
  schedule_end_time DATETIME,
  schedule_type STRING,
  bid_type STRING,
  identity_id STRING,
  tt_account_name STRING,
  cost NUMERIC,
  cost_per_order NUMERIC,
  cost_per_10_second_live_view NUMERIC,
  cost_per_live_view NUMERIC,
  max_delivery_budget NUMERIC,
  target_roi_budget NUMERIC,
  roi NUMERIC,
  roas_bid NUMERIC,
  orders NUMERIC,
  gross_revenue NUMERIC,
  net_cost NUMERIC,
  live_follows NUMERIC,
  live_views NUMERIC,
  `10_second_live_views` NUMERIC
)
PARTITION BY inserted_at
CLUSTER BY campaign_id;
