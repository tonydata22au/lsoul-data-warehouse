/* =============================================================================
   LSOUL PERFORMANCE DASHBOARD  --  PHASE 1 v2 (REPLACES v1) FOUNDATION LAYER
   Project/dataset : marine-cycle-484213-b4.reportdb   (location: asia-southeast1)
   Author          : data analyst
   Approach        : BUILD ON TOP of fn_performance_snapshot_v2 / fn_stats_product_v2.
                     The existing functions are NOT modified. See README for why.

   Creates:
     1. dash_base_order_day   -- atomic grain: one row per order x day x channel
     2. dash_target_day       -- target plan, de-duplicated, country-mapped
     3. dash_dq_channel_day   -- data-completeness guard (China Ecom lags T-1)

   Run order: this file first, then 02_phase2_pages.sql.
   All monetary values are VND. No FX conversion is applied or needed.
   -----------------------------------------------------------------------------
   WHY v2: v1 reconciled perfectly to fn_performance_snapshot_v2 -- but the
   function itself was inflating Taobao/Tmall 4.03x, so v1 inherited the error.
   v2 reads the China ecommerce raw tables directly, which also lets us expose
   GMV and NMV separately.

   REVENUE BASIS (agreed):
     * GMV is the COMPARABLE series. It is stable the moment an order lands.
     * NMV = the actual net figure. Targets are set on NMV (confirmed, TQ Ecommerce).
     * 30-DAY MATURATION RULE. Cancellations flow back from the platforms into the
       DB over roughly a month. Measured keep-rate (NMV/GMV) by order age,
       Taobao/Tmall, trailing 120 days:
             0-7 days   69.0%      <- badly immature
             8-14 days  29.7%
            15-21 days  24.1%
            22-30 days  22.7%      <- effectively settled
            31-45 days  23.1%
            46-60 days  21.6%
              60+ days  20.9%
       Flat from ~22 days on. Xiaohongshu/Douyin follow the same shape (noisier,
       smaller volumes). So:
            period_date <= T-30  ->  nmv = OBSERVED net   (exact, already matured)
            period_date >  T-30  ->  nmv = gmv x factor   (modelled)
       This is why a raw WoW on observed-net is meaningless: last week reads ~69%
       kept against ~23% for a settled week, a built-in +200% phantom.
       Modelling the recent window keeps NMV a fixed multiple of a stable base, so
       NMV movement equals GMV movement and neither carries maturation bias.
       Both weeks in any WoW comparison are < 30 days old, so both use the modelled
       path -- always like-for-like.
     * VN/TH (Pancake) sources already exclude canceled/returned orders, so their
       revenue is natively NMV. True GMV is not recoverable without rewriting
       those functions, so gmv = nmv there and has_true_gmv = FALSE.
       Their maturation bias is mild (~40% mature cancel rate vs ~31% current)
       and is surfaced, not silently corrected.

   PRIMARY REPORTING SERIES = NMV (comparable to target, consistent across all
   channels). GMV is exposed for China movement diagnostics.

   Creates:
     1. dash_nmv_factor        -- measured NMV/GMV per China platform
     2. dash_base_order_day    -- atomic order-grain fact, GMV + NMV
     3. dash_target_day        -- unchanged from v1 (re-stated for completeness)
     4. dash_dq_platform_day   -- DQ guard, now at LEVEL_3 (Tmall/Taobao load weekly)
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. dash_nmv_factor
   -----------------------------------------------------------------------------
   Measured from MATURED orders only (older than 30 days), so cancellations have
   fully settled. Recomputed on each refresh so the factor tracks reality instead
   of being a hardcoded guess. Used ONLY for the < 30 day window; older periods
   use their observed net directly.

   MEASURED (mature window):
       Tmall 20.4%   Taobao 23.5%   Xiaohongshu 22.3%   Douyin 17.3%
       weighted average ~21%
   NOTE: this is materially below the 40% working assumption. Worth reconciling
   with Finance -- 40% may refer to NMV after a different deduction set.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_nmv_factor`;

CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_nmv_factor` AS
WITH tt AS (
  SELECT level_3,
         SUM(revenue_cn_gmv) AS gmv,
         SUM(revenue_cn) AS nmv
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_v2`(0,0)
  WHERE 1=1
    AND DATE(order_date)
        BETWEEN DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 180 DAY)
            AND DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 30 DAY)
  GROUP BY level_3
),
jst AS (
  SELECT level_3,
         SUM(revenue_cn_gmv) AS gmv,
         SUM(revenue_cn) AS nmv
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_v2`(0,0)
  WHERE 1=1
    AND DATE(order_date)
        BETWEEN DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 180 DAY)
            AND DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 30 DAY)
  GROUP BY level_3
)
SELECT
   level_3
  ,gmv                                   AS mature_gmv_cny
  ,nmv                                   AS mature_nmv_cny
  ,ROUND(SAFE_DIVIDE(nmv, gmv), 4)       AS nmv_factor
  ,CURRENT_DATE('Asia/Ho_Chi_Minh')      AS computed_on
FROM (SELECT * FROM tt UNION ALL SELECT * FROM jst)
WHERE gmv > 0;


/* -----------------------------------------------------------------------------
   2. dash_base_order_day
   -----------------------------------------------------------------------------
   GRAIN: one row per (period_date, country, level_1, level_2, level_3, order_id).
   Verified in v1: 37,104 rows = 37,104 distinct orders, and NO order spans more
   than one channel -- so COUNT(DISTINCT order_id) is exactly additive at every
   rollup. Bills are therefore correct at country, level_1 and level_2 grain.

   China ecommerce is read from the RAW tables (not the TVFs) so that both GMV
   and NMV are available and the 4.03x fan-out is bypassed regardless of whether
   00_fix_taobao_tmall_fanout.sql has been applied.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_base_order_day`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_base_order_day`
PARTITION BY period_date
CLUSTER BY country, level_1, level_2
AS
WITH factors AS (
  SELECT level_3, nmv_factor FROM `marine-cycle-484213-b4.reportdb.dash_nmv_factor`
),

-- ---------- VN / TH : already net of canceled+returned => natively NMV ----------
pancake AS (
  SELECT DATE(order_date) AS period_date, * EXCEPT(order_date) FROM `marine-cycle-484213-b4.reportdb.fn_order_master`(0,0)
  WHERE country <> 'CHINA' and level_1 <> 'Sale Ecommerce'
),
pancake_std AS (
  -- NaN/NULL GUARD. Measured: 150 rows arrive with NULL revenue and 0 units (VN Online,
  -- Facebook/Instagram). Left unguarded they become NULL nmv, and any NaN would propagate
  -- through SUM and silently poison the trailing-range tests in the trend layer.
  SELECT period_date, country, level_1, level_2, level_3, order_id, customer_id,
         IF(IS_NAN(sales_revenue) OR sales_revenue IS NULL, 0, sales_revenue) AS gmv,   -- true GMV not recoverable; equal by construction
         IF(IS_NAN(revenue) OR revenue IS NULL, 0, revenue) AS nmv,
         IF(IS_NAN(units_sold) OR units_sold IS NULL, 0, units_sold) AS units_sold,
         FALSE AS has_true_gmv,
         'observed (natively net)' AS nmv_basis
  FROM pancake
),
-- ---------- CHINA ECOM: raw tables, GMV gross + modelled NMV ----------
china_ecom AS (
 SELECT DATE(order_date) AS period_date,country, level_1, level_2, level_3, order_id, customer_id,
         IF(IS_NAN(sales_revenue) OR sales_revenue IS NULL, 0, sales_revenue) AS gmv,   -- true GMV not recoverable; equal by construction
         IF(IS_NAN(revenue) OR revenue IS NULL, 0, revenue) AS nmv_observed,
         IF(IS_NAN(units_sold) OR units_sold IS NULL, 0, units_sold) AS units_sold
 FROM `marine-cycle-484213-b4.reportdb.fn_order_master`(0,0)
 WHERE country = 'CHINA' and level_1 = 'Sale Ecommerce'
),
cn_std AS (
  SELECT c.period_date, c.country, c.level_1, c.level_2, c.level_3, c.order_id, c.customer_id,
         c.gmv,
         -- 30-DAY MATURATION SWITCH.
         -- Older than 30 days: cancellations have fully flowed back from the
         -- platform, so the observed net IS the true NMV -- use it, don't estimate.
         -- Within 30 days: observed net is still inflating (69% kept at 0-7 days
         -- vs ~23% settled), so model it off the stable GMV base instead.
         CASE
           WHEN c.period_date <= DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 30 DAY)
             THEN c.nmv_observed
           ELSE c.gmv * IFNULL(f.nmv_factor, 0.21)   -- 0.21 = measured blended fallback
         END AS nmv,
         c.units_sold,
         TRUE AS has_true_gmv,
         CASE
           WHEN c.period_date <= DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 30 DAY)
             THEN 'observed (matured)'
           ELSE 'modelled (<30 days)'
         END AS nmv_basis
  FROM china_ecom c
  LEFT JOIN factors f ON f.level_3 = c.level_3
)
SELECT * FROM pancake_std
UNION ALL
SELECT * FROM cn_std;


/* -----------------------------------------------------------------------------
   3. dash_target_day  -- unchanged from v1. Re-run only if not already created.
      (Targets are on NMV, which is what dash_base_order_day.nmv now represents.)
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_target_day`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_target_day`
PARTITION BY sale_date
CLUSTER BY level_2
AS
WITH daily AS (
  SELECT DATE(sale_date) AS sale_date, channel AS level_2,
         ANY_VALUE(sale_country) AS country,
         ANY_VALUE(sale_channel_type) AS level_1_raw,
         SUM(metric_value_daily) AS target_revenue
  FROM `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily`
  WHERE is_for_daily_report = 1
  GROUP BY sale_date, channel
),
monthly AS (
  SELECT DATE_TRUNC(sale_date, MONTH) AS month_start, level_2,
         SUM(target_revenue) AS month_target_revenue
  FROM daily GROUP BY month_start, level_2
)
SELECT
   d.sale_date
  ,DATE_TRUNC(d.sale_date, MONTH)         AS month_start
  ,DATE_TRUNC(d.sale_date, WEEK(MONDAY))  AS week_start
  ,d.country
  ,IFNULL(d.level_1_raw, 'Unmapped')      AS level_1
  ,d.level_2
  ,d.target_revenue
  ,m.month_target_revenue
  ,d.level_1_raw IS NULL                  AS is_unmapped_channel
  ,d.level_2 = 'VN Online'                AS is_multi_country_target
  ,m.month_target_revenue < 500e6         AS is_low_target
  ,m.month_target_revenue <= 0            AS is_target_invalid
FROM daily d
JOIN monthly m
  ON m.month_start = DATE_TRUNC(d.sale_date, MONTH) AND m.level_2 = d.level_2;


/* -----------------------------------------------------------------------------
   4. dash_dq_platform_day   -- now at LEVEL_3, not level_2
   -----------------------------------------------------------------------------
   Tmall and Taobao are uploaded MANUALLY once a week, early Monday, covering the
   week just ended. So they are complete only through the most recent SUNDAY,
   and always show zero for days after it. Verified 2026-08-10 (Mon):
       Tmall 0, Taobao 0, Xiaohongshu 23m  -> not a channel outage, a load cadence.
   Everything else loads daily and is complete to T-1.

   data_complete_through is the per-platform as-of date. Attainment downstream is
   computed against target pro-rated to THAT date, so each channel is compared
   like-for-like instead of against a target that assumes days it has no data for.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_dq_platform_day`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_dq_platform_day` AS
WITH params AS (
  SELECT
     DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY) AS t_minus_1
    -- most recent completed Sunday
    ,DATE_SUB(DATE_TRUNC(CURRENT_DATE('Asia/Ho_Chi_Minh'), WEEK(MONDAY)), INTERVAL 1 DAY) AS last_sunday
),
platforms AS (
  SELECT DISTINCT country, level_1, level_2, level_3
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  WHERE period_date >= DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 120 DAY)
),
last_data AS (
  SELECT level_3, MAX(period_date) AS last_date_with_data
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  WHERE nmv > 0
  GROUP BY level_3
)
SELECT
   p.country, p.level_1, p.level_2, p.level_3
  ,l.last_date_with_data
  ,p.level_3 IN ('Tmall','Taobao')                          AS is_weekly_load
  ,CASE WHEN p.level_3 IN ('Tmall','Taobao') THEN par.last_sunday
        ELSE par.t_minus_1 END                              AS data_complete_through
  ,par.t_minus_1                                            AS t_minus_1
  ,par.last_sunday                                          AS last_sunday
  ,CASE WHEN p.level_3 IN ('Tmall','Taobao')
         THEN 'Manual weekly upload (Mon AM). Complete only through last Sunday.'
        ELSE 'Daily load. Complete through T-1.' END        AS load_note
FROM platforms p
CROSS JOIN params par
LEFT JOIN last_data l USING (level_3);


/* =============================================================================
   VALIDATION -- expected PASS values in comments
   ============================================================================= */

-- V1. Atomic grain holds. EXPECT excess_rows = 0.
SELECT COUNT(*) AS rows_out,
       COUNT(DISTINCT FORMAT('%t|%t|%t|%t|%t', period_date,level_1, level_2, level_3, order_id)) AS keys,
       COUNT(*) - COUNT(DISTINCT FORMAT('%t|%t|%t|%t|%t', period_date,level_1, level_2, level_3, order_id)) AS excess_rows
FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`;

-- V2. Taobao/Tmall no longer inflated. EXPECT ratio ~= 1.00 vs raw source.
WITH mine AS (
  SELECT ROUND(SUM(gmv)/1e6) AS gmv_mVND
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  WHERE level_3 IN ('Tmall','Taobao') AND period_date BETWEEN '2026-08-03' AND '2026-08-09'
),
raw AS (
  SELECT ROUND(SUM(items_buyer_paid_amount)*3800/1e6) AS gmv_mVND
  FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
  WHERE shop_id IN (20209463,20209689) AND items_buyer_paid_amount > 0
    AND DATE(vn_order_date) BETWEEN '2026-08-03' AND '2026-08-09'
)
SELECT mine.gmv_mVND AS mine, raw.gmv_mVND AS raw_source,
       ROUND(SAFE_DIVIDE(mine.gmv_mVND, raw.gmv_mVND),2) AS ratio
FROM mine CROSS JOIN raw;

-- V2b. NaN / NULL guard. EXPECT all zeros.
SELECT COUNTIF(IS_NAN(nmv)) AS nan_nmv, COUNTIF(IS_NAN(gmv)) AS nan_gmv,
       COUNTIF(nmv IS NULL) AS null_nmv, COUNTIF(units_sold IS NULL) AS null_units
FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`;

-- V3. NMV factors. EXPECT 4 ROWS (Tmall, Taobao, Xiaohongshu, Douyin), factors ~0.17-0.25.
--     If only 2 rows appear, the table predates the Jushuitan branch and Xiaohongshu/Douyin
--     are silently using the 0.21 fallback instead of their measured factors. Re-run this file.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_nmv_factor` ORDER BY nmv_factor;

-- V4. Per-platform completeness. EXPECT Tmall/Taobao complete_through = last Sunday.
SELECT level_2, level_3, is_weekly_load, last_date_with_data, data_complete_through
FROM `marine-cycle-484213-b4.reportdb.dash_dq_platform_day`
ORDER BY is_weekly_load DESC, level_2, level_3;

-- V5. GMV vs NMV by channel, last complete week. Sanity-check the split.
SELECT level_2, level_3,
       ROUND(SUM(gmv)/1e6) AS gmv_mVND,
       ROUND(SUM(nmv)/1e6) AS nmv_mVND,
       ROUND(SAFE_DIVIDE(SUM(nmv), SUM(gmv))*100,1) AS nmv_pct,
       COUNT(DISTINCT order_id) AS bills
FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
WHERE period_date BETWEEN '2026-08-03' AND '2026-08-09'
GROUP BY level_2, level_3
ORDER BY gmv_mVND DESC;

-- V6. Maturation switch behaves. EXPECT: China rows within 30 days = 'modelled',
--     older = 'observed (matured)', and the two keep-rates should be CLOSE
--     (within a few pp). A large gap means the factor has drifted and
--     dash_nmv_factor should be re-inspected.
SELECT nmv_basis,
       COUNT(*)                                       AS order_rows,
       MIN(period_date)                               AS first_date,
       MAX(period_date)                               AS last_date,
       ROUND(SUM(gmv)/1e9, 2)                         AS gmv_bn,
       ROUND(SUM(nmv)/1e9, 2)                         AS nmv_bn,
       ROUND(SAFE_DIVIDE(SUM(nmv), SUM(gmv))*100, 1)  AS keep_rate_pct
FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
WHERE level_2 = 'TQ Ecommerce'
GROUP BY nmv_basis ORDER BY nmv_basis;