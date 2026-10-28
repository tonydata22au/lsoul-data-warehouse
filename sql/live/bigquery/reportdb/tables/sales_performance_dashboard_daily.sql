CREATE TABLE `marine-cycle-484213-b4.reportdb.sales_performance_dashboard_daily`
(
  period_date DATE,
  week_start DATE,
  month_start DATE,
  country STRING,
  level_1 STRING,
  level_2 STRING,
  sales_revenue FLOAT64,
  revenue FLOAT64,
  units_sold FLOAT64,
  orders_by_channel INT64,
  cross_channel_order_rows INT64,
  missing_order_key_rows INT64,
  target_revenue FLOAT64,
  has_actual BOOL,
  has_target BOOL,
  model_refreshed_at TIMESTAMP,
  actual_through_date DATE
)
PARTITION BY period_date
CLUSTER BY country, level_1, level_2
OPTIONS(
  description="Sales Performance Dashboard"
);
