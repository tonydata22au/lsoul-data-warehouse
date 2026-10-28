CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_target_master(i_number_year_back INT64, i_type INT64)
AS
WITH base_daily AS (
    SELECT 
    DATE(order_date) AS order_date,
    EXTRACT(MONTH FROM order_date) AS order_month,
    country,
    level_1,
    level_2,
    level_3,
    SUM(sales_revenue) AS sales_revenue,
    SUM(revenue) AS revenue,
    SUM(units_sold) AS total_units_sold,
    COUNT(distinct order_id) AS total_orders,
    COUNT(distinct customer_id) AS total_customers,
    FROM `marine-cycle-484213-b4.reportdb.fn_order_master`(i_number_year_back,0)
    GROUP BY 1,2,3,4,5,6
  )
,base_daily_2 AS (
  SELECT *
  ,COUNT(distinct level_3) OVER (PARTITION BY order_month, level_2) AS count_level_3_per_level_2,
  FROM base_daily
)
,base_target_daily AS (
  SELECT DATE(sale_date) AS sale_date,
         sale_country AS country,
         sale_channel_type AS level_1, 
         channel AS level_2,
         SUM(metric_value_daily) OVER (PARTITION BY DATE(sale_date)) AS target_revenue_by_date,
         SUM(metric_value_daily) OVER (PARTITION BY DATE(sale_date),sale_country) AS target_revenue_per_country,
         SUM(metric_value_daily) OVER (PARTITION BY DATE(sale_date),channel) AS target_revenue_per_level_2
  FROM `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily`
  WHERE is_for_daily_report = 1
  --AND  channel IN (SELECT DISTINCT level_2 FROM base_daily)
)

,daily AS (
    SELECT
      IFNULL(order_date,t.sale_date) AS period_date,
      IFNULL(IFNULL(o.level_1,t.level_1),t.level_2) AS level_1,
      IFNULL(o.level_2,t.level_2) AS level_2,
      IFNULL(level_3,IFNULL(o.level_2, t.level_2)) AS level_3,
      IFNULL(o.country,t.country) AS country,
      IFNULL(sales_revenue,0) AS sales_revenue,
      IFNULL(revenue,0) AS revenue,
      IFNULL(target_revenue_per_country,0) AS target_revenue_per_country,
      IFNULL(target_revenue_by_date,0) AS target_revenue_by_date,
      IFNULL(target_revenue_per_level_2,0) AS target_revenue_per_level_2,
      IFNULL(total_units_sold,0) AS total_units_sold,
      IFNULL(total_orders,0) AS total_orders,
      IFNULL(total_customers,0) AS total_customers,
      CASE WHEN o.order_date IS NULL AND t.sale_date >= CURRENT_DATE() THEN 1 ELSE 0 END AS is_non_sale_data
    FROM base_daily_2 o
    FULL OUTER JOIN  base_target_daily t ON  t.sale_date = o.order_date  AND t.level_2 =  o.level_2 AND t.country = o.country
    WHERE 1=1
)
,daily_target AS (
    SELECT *
    ,IFNULL(SAFE_DIVIDE(target_revenue_per_level_2
                        ,COUNT(DISTINCT IFNULL(level_3, level_2)))
                      ,target_revenue_per_level_2) AS target_revenue_per_level_3
    ,IFNULL(SAFE_DIVIDE(target_revenue_per_level_2
                        ,COUNT(*))
                      ,target_revenue_per_level_2) AS target_revenue_per_level_3_grain
    FROM daily
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
)
  SELECT * FROM daily_target WHERE i_type = 0 OR  (is_non_sale_data = 0 AND i_type = 1);
