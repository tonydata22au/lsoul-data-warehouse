CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_performance_snapshot`(
  i_type INT64 -- not set yet
  ,i_number_year_back INT64 --0: current year
)
AS 
/*
Author: Toan Pham
Date: 28/07/2026
Comment: 
Metrics/KPIs:
Total Revenue Weekly
% Achievement Weekly
% Tăng trưởng doanh thu theo tuần (Revenue Growth WoW %)
Average Order Value (AOV)
Channels
Target vs Achievement

Testing:
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_performance_snapshot`(0,1) 
  where 1=1
AND DATE_TRUNC(period_date) >= "2026-07-01"
AND DATE(period_date) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
ORDER BY 1 DESC 
*/
(

WITH base_daily AS (
      SELECT
      period_date,
      DATE_TRUNC(period_date,MONTH) AS month_start,
      DATE_TRUNC(period_date, WEEK(MONDAY)) AS week_start,
      EXTRACT(WEEK FROM DATE_TRUNC(period_date, WEEK(MONDAY))) AS order_week,
      country,
      level_1,level_2,level_3,
      ANY_VALUE(target_revenue_per_level_2) AS target_revenue_per_level_2,
      ANY_VALUE(target_revenue_per_level_3) AS target_revenue_per_level_3,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(total_units_sold) AS units_sold,
      SUM(total_orders) AS order_confirmed,
      SUM(total_customers) AS total_customers
      FROM `marine-cycle-484213-b4.reportdb.fn_order_target_master`(0,0)
      WHERE DATE_TRUNC(period_date,MONTH)  <= DATE_TRUNC(CURRENT_DATE(),MONTH)
      GROUP BY 1, 2, 3, 4,5,6,7,8
)

,base_daily_target AS (
SELECT
      * EXCEPT (target_revenue_per_level_3)
      --,COUNT(*) OVER (PARTITION BY period_date,level_2 ORDER BY period_date) AS count_row_daily
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY period_date ORDER BY period_date) AS target_revenue_daily
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY week_start ORDER BY week_start) AS target_revenue_weekly
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY month_start ORDER BY month_start) AS target_revenue_monthly
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY period_date,country ORDER BY period_date) AS target_revenue_daily_country
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY week_start,country  ORDER BY week_start) AS target_revenue_weekly_country
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY period_date,country,level_1 ORDER BY period_date) AS target_revenue_daily_country_level_1
      ,SUM(target_revenue_per_level_3) OVER (PARTITION BY week_start,country,level_1  ORDER BY week_start) AS target_revenue_weekly_country_level_1
      ,target_revenue_per_level_3
      --Week revenue
     ,SUM(sales_revenue) OVER (PARTITION BY order_week ORDER BY order_week) AS weekly_sales_revenue
     ,SUM(sales_revenue) OVER (PARTITION BY order_week,country,level_3  ORDER BY order_week) AS weekly_sales_revenue_by_country_level_3
     ,SUM(sales_revenue) OVER (PARTITION BY order_week,country,level_1 ORDER BY order_week) AS weekly_sales_revenue_by_country_level_1
     ,SUM(sales_revenue) OVER (PARTITION BY order_week,level_2 ORDER BY order_week) AS weekly_sales_revenue_by_level_2
     ,SUM(revenue) OVER (PARTITION BY order_week ORDER BY order_week) AS weekly_revenue
     ,SUM(revenue) OVER (PARTITION BY order_week,country,level_3 ORDER BY order_week) AS weekly_revenue_by_country_level_3
     ,SUM(revenue) OVER (PARTITION BY order_week,country,level_1 ORDER BY order_week) AS weekly_revenue_by_country_level_1
     ,SUM(revenue) OVER (PARTITION BY order_week,level_2 ORDER BY order_week) AS weekly_revenue_by_level_2
    --  ,SUM(units_sold) OVER (PARTITION BY order_week,country,level_3 ORDER BY order_week) AS weekly_units_sold_by_country_level_3
    --  ,SUM(units_sold) OVER (PARTITION BY order_week,level_1 ORDER BY order_week) AS weekly_units_sold_by_level_1
    --  ,SUM(units_sold) OVER (PARTITION BY order_week,level_2 ORDER BY order_week) AS weekly_units_sold_by_level_2
     --Month revenue
     ,SUM(sales_revenue) OVER (PARTITION BY month_start ORDER BY month_start) AS monthly_sale_revenue
     ,SUM(sales_revenue) OVER (PARTITION BY month_start,country,level_3 ORDER BY month_start) AS monthly_sales_revenue_by_country_level_3
     ,SUM(sales_revenue) OVER (PARTITION BY month_start,level_1 ORDER BY month_start) AS monthly_sales_revenue_by_level_1
     ,SUM(sales_revenue) OVER (PARTITION BY month_start,level_2 ORDER BY month_start) AS monthly_sales_revenue_by_level_2
     ,SUM(revenue) OVER (PARTITION BY month_start ORDER BY month_start) AS monthly_revenue
     ,SUM(revenue) OVER (PARTITION BY month_start,country,level_3 ORDER BY month_start) AS monthly_revenue_by_country_level_3
     ,SUM(revenue) OVER (PARTITION BY month_start,level_1 ORDER BY month_start) AS monthly_revenue_by_level_1
     ,SUM(revenue) OVER (PARTITION BY month_start,level_2 ORDER BY month_start) AS monthly_revenue_by_level_2
    --  ,SUM(units_sold) OVER (PARTITION BY month_start,country,level_3 ORDER BY month_start) AS monthly_units_sold_by_country_level_3
    --  ,SUM(units_sold) OVER (PARTITION BY month_start,level_1 ORDER BY month_start) AS monthly_units_sold_by_level_1
    --  ,SUM(units_sold) OVER (PARTITION BY month_start,level_2 ORDER BY month_start) AS monthly_units_sold_by_level_2
    FROM base_daily 
    WHERE 1=1
    ORDER BY 1 DESC 
)

-- WoW Lags by Week
,weekly_with_lags_by_week AS (
  SELECT week_start
  ,IFNULL(LAG(weekly_sales_revenue) OVER (ORDER BY week_start),weekly_sales_revenue) AS prev_weekly_sales_revenue
  ,IFNULL(LAG(weekly_revenue) OVER (ORDER BY week_start),weekly_revenue) AS prev_weekly_revenue
  --,LAG(weekly_units_sold_by_country_level_3) OVER (PARTITION BY country,level_3  ORDER BY week_start) AS prev_weekly_units_sold_country_level_3
  FROM (SELECT week_start,weekly_sales_revenue,weekly_revenue
  --,weekly_units_sold_by_country_level_3 
  FROM base_daily_target GROUP BY 1,2,3)
  ORDER BY 1 DESC,2
)



-- WoW Lags by Country
,weekly_with_lags_by_country_level_3 AS (
  SELECT week_start,country,level_3 
  ,LAG(weekly_sales_revenue_by_country_level_3) OVER (PARTITION BY country,level_3 ORDER BY week_start) AS prev_weekly_sales_revenue_country_level_3
  ,LAG(weekly_revenue_by_country_level_3) OVER (PARTITION BY country,level_3  ORDER BY week_start) AS prev_weekly_revenue_country_level_3
  --,LAG(weekly_units_sold_by_country_level_3) OVER (PARTITION BY country,level_3  ORDER BY week_start) AS prev_weekly_units_sold_country_level_3
  FROM (SELECT week_start,country,level_3 ,weekly_sales_revenue_by_country_level_3,weekly_revenue_by_country_level_3
  --,weekly_units_sold_by_country_level_3 
  FROM base_daily_target GROUP BY 1,2,3,4,5)
  ORDER BY 1 DESC,2
)

-- WoW Lags by Country & Level 1
,weekly_with_lags_by_country_level_1 AS (
  SELECT week_start,country,level_1
  , LAG(weekly_sales_revenue_by_country_level_1) OVER (PARTITION BY country,level_1 ORDER BY week_start) AS prev_weekly_sales_revenue_country_level_1
  , LAG(weekly_revenue_by_country_level_1) OVER (PARTITION BY country,level_1 ORDER BY week_start) AS prev_weekly_revenue_country_level_1
  --, LAG(weekly_units_sold_by_level_1) OVER (PARTITION BY level_1 ORDER BY week_start) AS prev_weekly_units_sold_level_1
  FROM (SELECT week_start,country,level_1,weekly_sales_revenue_by_country_level_1,weekly_revenue_by_country_level_1
  --,weekly_units_sold_by_level_1 
  FROM base_daily_target GROUP BY 1,2,3,4,5)
  ORDER BY 1 DESC,2
)

-- WoW Lags by Level 2
,weekly_with_lags_by_level_2 AS (
  SELECT week_start,level_2
  , LAG(weekly_sales_revenue_by_level_2) OVER (PARTITION BY level_2 ORDER BY week_start) AS prev_weekly_sales_revenue_level_2
  , LAG(weekly_revenue_by_level_2) OVER (PARTITION BY level_2 ORDER BY week_start) AS prev_weekly_revenue_level_2
  --, LAG(weekly_units_sold_by_level_2) OVER (PARTITION BY level_2 ORDER BY week_start) AS prev_weekly_units_sold_level_2
  FROM (SELECT week_start,level_2,weekly_sales_revenue_by_level_2,weekly_revenue_by_level_2
  --,weekly_units_sold_by_level_2 
  FROM base_daily_target GROUP BY 1,2,3,4)
  ORDER BY 1 DESC,2
)

-- MoM Lags by Month
,monthly_with_lags_by_month AS (
  SELECT month_start
  ,IFNULL(LAG(monthly_sale_revenue) OVER (ORDER BY month_start),monthly_sale_revenue) AS prev_monthly_sales_revenue
  ,IFNULL(LAG(monthly_revenue) OVER (ORDER BY month_start),monthly_revenue) AS prev_monthly_revenue
  --,LAG(monthly_units_sold_by_country_level_3) OVER (PARTITION BY country,level_3 ORDER BY month_start) AS prev_monthly_units_sold_country_level_3
  FROM (SELECT month_start,monthly_sale_revenue,monthly_revenue
  --,monthly_units_sold_by_country_level_3 
  FROM base_daily_target GROUP BY 1,2,3)
  ORDER BY 1 DESC,2
)

-- MoM Lags by Country & Level 3
,monthly_with_lags_by_country_level_3 AS (
  SELECT month_start,country,level_3
  ,LAG(monthly_sales_revenue_by_country_level_3) OVER (PARTITION BY country,level_3 ORDER BY month_start) AS prev_monthly_sales_revenue_country_level_3
  ,LAG(monthly_revenue_by_country_level_3) OVER (PARTITION BY country,level_3 ORDER BY month_start) AS prev_monthly_revenue_country_level_3
  --,LAG(monthly_units_sold_by_country_level_3) OVER (PARTITION BY country,level_3 ORDER BY month_start) AS prev_monthly_units_sold_country_level_3
  FROM (SELECT month_start,country,level_3,monthly_sales_revenue_by_country_level_3,monthly_revenue_by_country_level_3
  --,monthly_units_sold_by_country_level_3 
  FROM base_daily_target GROUP BY 1,2,3,4,5)
  ORDER BY 1 DESC,2
)

  SELECT
  b.*
  ,w.prev_weekly_sales_revenue,w.prev_weekly_revenue
  ,c.prev_weekly_sales_revenue_country_level_3,c.prev_weekly_revenue_country_level_3 --,c.prev_weekly_units_sold_country_level_3
  ,l1.prev_weekly_sales_revenue_country_level_1,l1.prev_weekly_revenue_country_level_1 --,l1.prev_weekly_units_sold_level_1
  ,l2.prev_weekly_sales_revenue_level_2,l2.prev_weekly_revenue_level_2 --,l2.prev_weekly_units_sold_level_2
  ,m.prev_monthly_sales_revenue, m.prev_monthly_revenue
  ,ml3.prev_monthly_sales_revenue_country_level_3, ml3.prev_monthly_revenue_country_level_3 --,ml3.prev_monthly_units_sold_country_level_3
  FROM base_daily_target b
  LEFT JOIN weekly_with_lags_by_week w ON b.week_start = w.week_start
  LEFT JOIN weekly_with_lags_by_country_level_3 c ON b.week_start = c.week_start AND b.country = c.country AND b.level_3 = c.level_3
  LEFT JOIN weekly_with_lags_by_country_level_1 l1 ON b.week_start = l1.week_start  AND b.country = l1.country AND b.level_1 = l1.level_1 
  LEFT JOIN weekly_with_lags_by_level_2 l2 ON b.week_start = l2.week_start AND b.level_2 = l2.level_2
  LEFT JOIN monthly_with_lags_by_month m ON b.month_start = m.month_start
  LEFT JOIN monthly_with_lags_by_country_level_3 ml3 ON b.month_start = ml3.month_start AND b.country = ml3.country AND b.level_3 = ml3.level_3
  where 1=1
  order by 1 desc, country, level_1, level_2, level_3
);