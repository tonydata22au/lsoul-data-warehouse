CREATE TABLE `marine-cycle-484213-b4.stg_tiktok.stg_tiktok_gmv_max_report`
(
  proc_date DATE,
  inserted_at DATE,
  campaign_id STRING,
  campaign_name STRING,
  operation_status STRING,
  schedule_end_time DATETIME,
  schedule_start_time DATETIME,
  schedule_type STRING,
  cost NUMERIC,
  cost_per_order NUMERIC,
  cost_per_10_second_live_view NUMERIC,
  cost_per_live_view NUMERIC,
  gross_revenue NUMERIC,
  net_cost NUMERIC,
  target_roi_budget NUMERIC,
  roi NUMERIC,
  orders NUMERIC,
  roas_bid NUMERIC,
  max_delivery_budget NUMERIC,
  `10_second_live_views` NUMERIC,
  bid_type STRING,
  identity_id STRING,
  live_follows NUMERIC,
  live_views NUMERIC,
  tt_account_name STRING
)
PARTITION BY proc_date;
