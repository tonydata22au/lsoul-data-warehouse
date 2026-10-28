CREATE TABLE `marine-cycle-484213-b4.reportdb.sales_performance_dashboard_order`
(
  period_date DATE,
  country STRING,
  level_1 STRING,
  level_2 STRING,
  level_3 STRING,
  order_id STRING,
  customer_id STRING,
  sales_revenue FLOAT64,
  revenue FLOAT64,
  units_sold FLOAT64,
  week_start DATE,
  month_start DATE,
  order_channel_key STRING,
  order_channel_count INT64,
  is_cross_channel_order BOOL,
  model_refreshed_at TIMESTAMP,
  actual_through_date DATE
)
PARTITION BY period_date
CLUSTER BY country, level_1, level_2, level_3
OPTIONS(
  description="Sales Performance Dashboard"
);
