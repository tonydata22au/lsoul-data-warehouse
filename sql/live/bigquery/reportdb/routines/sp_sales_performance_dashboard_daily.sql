CREATE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_sales_performance_dashboard_daily()
BEGIN
  DECLARE model_refreshed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  DECLARE actual_through_date DATE DEFAULT
    DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY);

  -- 1. Cập nhật bảng chi tiết đơn hàng.
  CREATE OR REPLACE TABLE
    `marine-cycle-484213-b4.reportdb.sales_performance_dashboard_order`
  PARTITION BY period_date
  CLUSTER BY country, level_1, level_2, level_3
  OPTIONS (
    description = 'Sales Performance Dashboard'
  )
  AS
  WITH source_orders AS (
    SELECT
      DATE(order_date) AS period_date,
      country,
      level_1,
      level_2,
      level_3,
      CAST(order_id AS STRING) AS order_id,
      CAST(customer_id AS STRING) AS customer_id,
      sales_revenue,
      revenue,
      units_sold
    FROM
      `marine-cycle-484213-b4.reportdb.fn_order_master`(0, 0)
    WHERE
      DATE(order_date) <= actual_through_date
  ),
  order_channel_counts AS (
    SELECT
      country,
      order_id,
      COUNT(DISTINCT TO_JSON_STRING(
        STRUCT(level_1, level_2)
      )) AS order_channel_count
    FROM source_orders
    WHERE
      order_id IS NOT NULL
      AND TRIM(order_id) != ''
    GROUP BY country, order_id
  )
  SELECT
    s.*,
    DATE_TRUNC(s.period_date, WEEK(MONDAY)) AS week_start,
    DATE_TRUNC(s.period_date, MONTH) AS month_start,
    CASE
      WHEN s.order_id IS NULL OR TRIM(s.order_id) = '' THEN NULL
      ELSE TO_JSON_STRING(
        STRUCT(
          s.country AS country,
          s.level_1 AS level_1,
          s.level_2 AS level_2,
          s.order_id AS order_id
        )
      )
    END AS order_channel_key,
    COALESCE(c.order_channel_count, 0) AS order_channel_count,
    COALESCE(c.order_channel_count > 1, FALSE)
      AS is_cross_channel_order,
    model_refreshed_at AS model_refreshed_at,
    actual_through_date AS actual_through_date
  FROM source_orders s
  LEFT JOIN order_channel_counts c
    ON s.country = c.country
    AND s.order_id = c.order_id;

  -- 2. Tổng hợp theo ngày và ghép mục tiêu.
  CREATE OR REPLACE TABLE
    `marine-cycle-484213-b4.reportdb.sales_performance_dashboard_daily`
  PARTITION BY period_date
  CLUSTER BY country, level_1, level_2
  OPTIONS (
    description = 'Sales Performance Dashboard'
  )
  AS
  WITH actual_daily AS (
    SELECT
      period_date,
      country,
      level_1,
      level_2,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(units_sold) AS units_sold,
      COUNT(DISTINCT order_channel_key) AS orders_by_channel,
      COUNTIF(is_cross_channel_order) AS cross_channel_order_rows,
      COUNTIF(order_channel_key IS NULL) AS missing_order_key_rows,
      0.0 AS target_revenue,
      TRUE AS has_actual,
      FALSE AS has_target
    FROM
      `marine-cycle-484213-b4.reportdb.sales_performance_dashboard_order`
    GROUP BY period_date, country, level_1, level_2
  ),
  target_daily AS (
    SELECT
      DATE(sale_date) AS period_date,
      sale_country AS country,
      COALESCE(sale_channel_type, channel) AS level_1,
      channel AS level_2,
      0.0 AS sales_revenue,
      0.0 AS revenue,
      0.0 AS units_sold,
      0 AS orders_by_channel,
      0 AS cross_channel_order_rows,
      0 AS missing_order_key_rows,
      SUM(metric_value_daily) AS target_revenue,
      FALSE AS has_actual,
      TRUE AS has_target
    FROM
      `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily`
    WHERE
      is_for_daily_report = 1
      AND sale_date IS NOT NULL
    GROUP BY period_date, country, level_1, level_2
  ),
  combined AS (
    SELECT * FROM actual_daily
    UNION ALL
    SELECT * FROM target_daily
  )
  SELECT
    period_date,
    DATE_TRUNC(period_date, WEEK(MONDAY)) AS week_start,
    DATE_TRUNC(period_date, MONTH) AS month_start,
    country,
    level_1,
    level_2,
    SUM(sales_revenue) AS sales_revenue,
    SUM(revenue) AS revenue,
    SUM(units_sold) AS units_sold,
    SUM(orders_by_channel) AS orders_by_channel,
    SUM(cross_channel_order_rows) AS cross_channel_order_rows,
    SUM(missing_order_key_rows) AS missing_order_key_rows,
    SUM(target_revenue) AS target_revenue,
    LOGICAL_OR(has_actual) AS has_actual,
    LOGICAL_OR(has_target) AS has_target,
    model_refreshed_at AS model_refreshed_at,
    actual_through_date AS actual_through_date
  FROM combined
  GROUP BY period_date, country, level_1, level_2;

END;
