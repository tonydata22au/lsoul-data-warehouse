CREATE TABLE `marine-cycle-484213-b4.reportdb.report_revenue_by_channel_sku_daily`
(
  period_date DATE,
  level_1 STRING,
  level_2 STRING,
  level_3 STRING,
  country STRING,
  sales_revenue FLOAT64,
  revenue FLOAT64,
  target_revenue_per_country FLOAT64,
  target_revenue_by_date FLOAT64,
  target_revenue_per_level_2 FLOAT64,
  total_units_sold FLOAT64,
  total_orders INT64,
  total_customers INT64,
  is_non_sale_data INT64,
  target_revenue_per_level_3 FLOAT64,
  target_revenue_per_level_3_grain FLOAT64
);
