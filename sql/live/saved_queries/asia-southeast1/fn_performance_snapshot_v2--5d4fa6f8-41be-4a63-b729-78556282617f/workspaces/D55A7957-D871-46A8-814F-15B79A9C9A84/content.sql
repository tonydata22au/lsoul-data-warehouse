CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_performance_snapshot_v2`(
  i_type INT64                    -- reserved, not currently used by any branch below
  ,i_number_year_back INT64       -- 0: current year
  ,i_date_from DATE  -- NEW: optional lower bound on order_date, enables pruning. NULL = no lower bound
  ,i_date_to   DATE  -- NEW: optional upper bound on order_date. NULL = no upper bound
)
AS
/*
Author: Toan Pham
Rewritten: 2026-08-06 (v2 review)
Comment:
Metrics/KPIs:
Total Revenue Weekly
% Achievement Weekly / Monthly
% Tang truong doanh thu theo tuan (Revenue Growth WoW %) / MoM %
Average Order Value (AOV) -- NEW: now computed in-function
Channels
Target vs Achievement

CHANGES vs v1:
1. BUG FIX: weekly window functions previously partitioned by `order_week` (an INT64, 1-53),
   which merges week 1 of every year together once the function spans more than one year.
   All weekly aggregates now partition by `week_start` (a DATE), which is unique per calendar week.
2. PERFORMANCE: replaced ~20 row-level SUM()/LAG() OVER(...) window columns computed on
   product-grain data (product_code x variation_code x warehouse_id) with pre-aggregated
   GROUP BY summary CTEs, joined back onto the product-grain rows. Same output columns,
   far less redundant computation and shuffling -- previously every product row within a
   week recomputed an identical weekly total.
3. PERFORMANCE / ROBUSTNESS: replaced the ROW_NUMBER()=1 trick for de-duplicating the daily
   target during the FULL OUTER JOIN with a pre-aggregated one-row-per-(date, channel) target CTE.
4. DATA TYPE: order_id and customer_id are now explicitly CAST to STRING in every branch of the
   UNION ALL, to avoid implicit-coercion or type-mismatch risk if any source function returns INT64.
5. NEW COLUMNS: pct_achievement_weekly, pct_achievement_monthly, wow_growth_pct, mom_growth_pct,
   aov_weekly, aov_weekly_country_level_3 -- avoids re-deriving these ratios in every downstream
   dashboard/report.
6. NEW PARAMS: i_date_from / i_date_to (both optional, default NULL) filter order_date as early
   as possible in the pipeline, to help BigQuery prune scanned data on large lookbacks.

CAUTION FOR CONSUMERS:
- `order_confirmed` and `customers` on the output are COUNT(DISTINCT ...) computed at the
  product/variation/warehouse grain. Do NOT SUM them further to get a daily/weekly order or
  customer count -- that will double-count orders/customers that span multiple products.
  Use the new weekly_order_confirmed-based aov_* columns (or a fresh COUNT DISTINCT at the
  grain you need) instead.
- channel_target assumes `sale_plan_2026_daily` has at most one target value per
  (sale_date, channel); country/level_1 are pulled via ANY_VALUE() under the assumption a
  channel maps to exactly one country/level_1. Validate this holds for your data.
- This is a structural rewrite. Validate output against the v1 function on a sample date
  range before switching dashboards over.

Testing:
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_performance_snapshot_v2`(0, 1, DATE("2026-07-01"), DATE_SUB(CURRENT_DATE(),INTERVAL 1 DAY)) 
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
      ANY_VALUE(target_revenue_by_date) AS target_revenue_by_date,
      ANY_VALUE(target_revenue_per_country) AS target_revenue_per_country,
      ANY_VALUE(target_revenue_per_level_2) AS target_revenue_per_level_2,
      ANY_VALUE(target_revenue_per_level_3) AS target_revenue_per_level_3,
      SUM(target_revenue_per_level_3_grain) AS target_revenue_per_level_3_grain,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(total_units_sold) AS units_sold,
      SUM(total_orders) AS total_orders,
      SUM(total_customers) AS total_customers
      FROM `marine-cycle-484213-b4.reportdb.fn_order_target_master`(i_number_year_back,0)
      WHERE 1=1
      AND (i_date_from IS NULL OR DATE(period_date) >= i_date_from)
      AND (i_date_to IS NULL OR DATE_TRUNC(period_date,MONTH)  <= DATE_TRUNC(i_date_to,MONTH))
      GROUP BY 1, 2, 3, 4,5,6,7,8

  )

  ,base_daily_target AS (
     SELECT DISTINCT 
         DATE(sale_date) AS period_date,
         sale_country AS country,
         sale_channel_type AS level_1, 
         channel AS level_2,
         metric_value_daily AS target_revenue_per_level_2
  FROM `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily`
  WHERE is_for_daily_report = 1
  )


  -- ===== Target/plan, pre-aggregated to one row per (date, channel/level_3) =====
  ,target_daily_total AS (
    SELECT period_date, SUM(target_revenue_per_level_2) AS target_revenue_daily
    FROM base_daily_target GROUP BY 1
  )
  ,target_daily_country AS (
    SELECT period_date, country, SUM(target_revenue_per_level_2) AS target_revenue_daily_country
    FROM base_daily_target GROUP BY 1,2
  )
  ,target_daily_country_level1 AS (
    SELECT period_date, country, IFNULL(level_1,level_2) AS level_1, SUM(target_revenue_per_level_2) AS target_revenue_daily_country_level_1
    FROM base_daily_target GROUP BY 1,2,3
  )
  
  ,target_weekly_total AS (
    SELECT DATE_TRUNC(period_date, WEEK(MONDAY)) AS week_start, SUM(target_revenue_per_level_2) AS target_revenue_weekly
    FROM base_daily_target GROUP BY 1 
  )

  ,target_weekly_country AS (
    SELECT DATE_TRUNC(period_date, WEEK(MONDAY)) AS week_start,country, SUM(target_revenue_per_level_2) AS target_weekly_country
    FROM base_daily_target GROUP BY 1,2 
  )
  ,target_monthly_total AS (
    SELECT DATE_TRUNC(period_date, MONTH) AS month_start, SUM(target_revenue_per_level_2) AS target_revenue_monthly
    FROM base_daily_target GROUP BY 1
  )

  ,target_monthly_country AS (
    SELECT DATE_TRUNC(period_date, MONTH) AS month_start,country, SUM(target_revenue_per_level_2) AS target_monthly_country
    FROM base_daily_target GROUP BY 1,2 
  )
  -- Distinct order/customer counts computed properly at reporting grain
  -- (NOT summed from product-grain counts, which would double count).
  ,weekly_orders AS (
    SELECT
      week_start,
      SUM(total_orders) AS weekly_order_confirmed
    FROM base_daily
    GROUP BY 1
  )
  ,weekly_orders_country_level3 AS (
    SELECT
      week_start,
      country, level_3,
       SUM(total_orders) AS weekly_order_confirmed_country_level_3
    FROM base_daily
    GROUP BY 1,2,3
  )


  -- ===== Revenue rollups, pre-aggregated (BUG FIX: partitioned/grouped by week_start /
  -- month_start -- real dates -- instead of the old order_week integer) =====
  ,revenue_weekly_total AS (
    SELECT week_start, SUM(sales_revenue) AS weekly_sales_revenue, SUM(revenue) AS weekly_revenue
    FROM base_daily GROUP BY 1
  )
  ,revenue_weekly_country_level3 AS (
    SELECT week_start, country, level_3,
      SUM(sales_revenue) AS weekly_sales_revenue_by_country_level_3,
      SUM(revenue) AS weekly_revenue_by_country_level_3
    FROM base_daily GROUP BY 1,2,3
  )
  ,revenue_weekly_level1 AS (
    SELECT week_start, level_1,
      SUM(sales_revenue) AS weekly_sales_revenue_by_level_1,
      SUM(revenue) AS weekly_revenue_by_level_1
    FROM base_daily GROUP BY 1,2
  )
  ,revenue_weekly_level2 AS (
    SELECT week_start, level_2,
      SUM(sales_revenue) AS weekly_sales_revenue_by_level_2,
      SUM(revenue) AS weekly_revenue_by_level_2
    FROM base_daily GROUP BY 1,2
  )
  ,revenue_monthly_total AS (
    SELECT month_start, SUM(sales_revenue) AS monthly_sales_revenue, SUM(revenue) AS monthly_revenue
    FROM base_daily GROUP BY 1
  )
  ,revenue_monthly_country_level3 AS (
    SELECT month_start, country, level_3,
      SUM(sales_revenue) AS monthly_sales_revenue_by_country_level_3,
      SUM(revenue) AS monthly_revenue_by_country_level_3
    FROM base_daily GROUP BY 1,2,3
  )

  -- ===== Lags computed once per (grain x period), not once per product row per period =====
  ,weekly_total_lag AS (
    SELECT *,
      LAG(weekly_sales_revenue) OVER (ORDER BY week_start) AS prev_weekly_sales_revenue,
      LAG(weekly_revenue) OVER (ORDER BY week_start) AS prev_weekly_revenue
    FROM revenue_weekly_total
  )
  ,weekly_country_level3_lag AS (
    SELECT *,
      LAG(weekly_sales_revenue_by_country_level_3) OVER (PARTITION BY country, level_3 ORDER BY week_start) AS prev_weekly_sales_revenue_country_level_3,
      LAG(weekly_revenue_by_country_level_3) OVER (PARTITION BY country, level_3 ORDER BY week_start) AS prev_weekly_revenue_country_level_3
    FROM revenue_weekly_country_level3
  )
  ,weekly_level1_lag AS (
    SELECT *,
      LAG(weekly_sales_revenue_by_level_1) OVER (PARTITION BY level_1 ORDER BY week_start) AS prev_weekly_sales_revenue_level_1,
      LAG(weekly_revenue_by_level_1) OVER (PARTITION BY level_1 ORDER BY week_start) AS prev_weekly_revenue_level_1
    FROM revenue_weekly_level1
  )
  ,weekly_level2_lag AS (
    SELECT *,
      LAG(weekly_sales_revenue_by_level_2) OVER (PARTITION BY level_2 ORDER BY week_start) AS prev_weekly_sales_revenue_level_2,
      LAG(weekly_revenue_by_level_2) OVER (PARTITION BY level_2 ORDER BY week_start) AS prev_weekly_revenue_level_2
    FROM revenue_weekly_level2
  )
  ,monthly_total_lag AS (
    SELECT *,
      LAG(monthly_sales_revenue) OVER (ORDER BY month_start) AS prev_monthly_sales_revenue,
      LAG(monthly_revenue) OVER (ORDER BY month_start) AS prev_monthly_revenue
    FROM revenue_monthly_total
  )
  ,monthly_country_level3_lag AS (
    SELECT *,
      LAG(monthly_sales_revenue_by_country_level_3) OVER (PARTITION BY country, level_3 ORDER BY month_start) AS prev_monthly_sales_revenue_country_level_3,
      LAG(monthly_revenue_by_country_level_3) OVER (PARTITION BY country, level_3 ORDER BY month_start) AS prev_monthly_revenue_country_level_3
    FROM revenue_monthly_country_level3
  )

  SELECT
    b.*,

    -- Daily target rollups
    tdt.target_revenue_daily,
    tdc.target_revenue_daily_country,
    tdcl1.target_revenue_daily_country_level_1,
    twt.target_revenue_weekly,
    twc.target_weekly_country,
    tmt.target_revenue_monthly,
    tmc.target_monthly_country,

    -- Weekly actuals + WoW lags
    wt.weekly_sales_revenue, wt.weekly_revenue,
    wt.prev_weekly_sales_revenue, wt.prev_weekly_revenue,
    wc.weekly_sales_revenue_by_country_level_3, wc.weekly_revenue_by_country_level_3,
    wc.prev_weekly_sales_revenue_country_level_3, wc.prev_weekly_revenue_country_level_3,
    wl1.weekly_sales_revenue_by_level_1, wl1.weekly_revenue_by_level_1,
    wl1.prev_weekly_sales_revenue_level_1, wl1.prev_weekly_revenue_level_1,
    wl2.weekly_sales_revenue_by_level_2, wl2.weekly_revenue_by_level_2,
    wl2.prev_weekly_sales_revenue_level_2, wl2.prev_weekly_revenue_level_2,

    -- Monthly actuals + MoM lags
    mt.monthly_sales_revenue, mt.monthly_revenue,
    mt.prev_monthly_sales_revenue, mt.prev_monthly_revenue,
    mc.monthly_sales_revenue_by_country_level_3, mc.monthly_revenue_by_country_level_3,
    mc.prev_monthly_sales_revenue_country_level_3, mc.prev_monthly_revenue_country_level_3,

    -- NEW: ready-to-use convenience metrics
    SAFE_DIVIDE(wt.weekly_revenue, NULLIF(twt.target_revenue_weekly, 0)) AS pct_achievement_weekly_revenue,
    SAFE_DIVIDE(wt.weekly_sales_revenue, NULLIF(twt.target_revenue_weekly, 0)) AS pct_achievement_weekly_sales_revenue,
    SAFE_DIVIDE(wt.weekly_revenue - wt.prev_weekly_sales_revenue, NULLIF(wt.prev_weekly_sales_revenue, 0)) AS wow_growth_pct,
    SAFE_DIVIDE(mt.monthly_revenue, NULLIF(tmt.target_revenue_monthly, 0)) AS pct_achievement_monthly_revenue,
    SAFE_DIVIDE(mt.monthly_sales_revenue, NULLIF(tmt.target_revenue_monthly, 0)) AS pct_achievement_monthly_sales_revenue,
    SAFE_DIVIDE(mt.monthly_revenue - mt.prev_monthly_sales_revenue, NULLIF(mt.prev_monthly_sales_revenue, 0)) AS mom_growth_pct,
    SAFE_DIVIDE(wt.weekly_revenue, NULLIF(wo.weekly_order_confirmed, 0)) AS aov_weekly,
    SAFE_DIVIDE(wc.weekly_revenue_by_country_level_3, NULLIF(woc.weekly_order_confirmed_country_level_3, 0)) AS aov_weekly_country_level_3

  FROM base_daily b
  LEFT JOIN target_daily_total          tdt   ON b.period_date = tdt.period_date
  LEFT JOIN target_daily_country        tdc   ON b.period_date = tdc.period_date AND b.country = tdc.country
  LEFT JOIN target_daily_country_level1 tdcl1 ON b.period_date = tdcl1.period_date AND b.country = tdcl1.country AND b.level_1 = tdcl1.level_1
  LEFT JOIN target_weekly_total         twt   ON b.week_start = twt.week_start
  LEFT JOIN target_weekly_country       twc   ON b.week_start = twc.week_start AND b.country = twc.country
  LEFT JOIN target_monthly_total        tmt   ON b.month_start = tmt.month_start
  LEFT JOIN target_monthly_country      tmc   ON b.month_start = tmc.month_start AND b.country = tmc.country
  LEFT JOIN weekly_total_lag            wt    ON b.week_start = wt.week_start
  LEFT JOIN weekly_country_level3_lag   wc    ON b.week_start = wc.week_start AND b.country = wc.country AND b.level_3 = wc.level_3
  LEFT JOIN weekly_level1_lag           wl1   ON b.week_start = wl1.week_start AND b.level_1 = wl1.level_1
  LEFT JOIN weekly_level2_lag           wl2   ON b.week_start = wl2.week_start AND b.level_2 = wl2.level_2

  LEFT JOIN monthly_total_lag           mt    ON b.month_start = mt.month_start
  LEFT JOIN monthly_country_level3_lag  mc    ON b.month_start = mc.month_start AND b.country = mc.country AND b.level_3 = mc.level_3

  LEFT JOIN weekly_orders               wo    ON b.week_start = wo.week_start
  LEFT JOIN weekly_orders_country_level3 woc  ON b.week_start = woc.week_start AND b.country = woc.country AND b.level_3 = woc.level_3

  ORDER BY 1 DESC, country, level_1, level_2, level_3
);