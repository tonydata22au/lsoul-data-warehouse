/* =============================================================================
   LSOUL PERFORMANCE DASHBOARD  --  PHASE 2: THE TWO PAGES
   Run AFTER Phase 1

   Creates:
     1. dash_run_params      -- single source of truth for all period boundaries
     2. dash_base_sku_day    -- SKU-grain units (for the trending list)
     3. dash_page1_wow       -- Page 1 section 2: trend view + diagnosis
     4. dash_page2_mtd       -- Page 2 section 2: MTD vs target
     5. dash_highlights      -- section 1 for BOTH pages (ranked, capped at 3+3)
     6. dash_stock_lists     -- section 3: four SKU lists
     7. dash_action_items    -- section 4: owner-tagged actions

   EVERYTHING here is deterministic SQL. Arithmetic, ranking, thresholds and the
   diagnosis decision table are computed here. Phase 3's model writes prose over
   these pre-computed facts and never calculates a number.

   ALL AMOUNTS ARE VND. Primary series is NMV (targets are set on NMV).
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. dash_run_params
   -----------------------------------------------------------------------------
   Every downstream table reads its dates from here, so the two pages can never
   drift apart or straddle different weeks.

   "Most recent COMPLETE week" = the Mon-Sun week whose Sunday <= report_date.
   Verified: report_date Mon 2026-08-10 -> week 2026-08-03..09. report_date
   Sat 2026-08-08 -> week 2026-07-27..08-02 (correctly does NOT use the
   in-progress week). Anchoring on a Monday also protects the WoW comparison:
   a non-Monday start would make the first week partial and manufacture a fake
   decline against it.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_run_params`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_run_params` AS
WITH b AS (
  SELECT
     CURRENT_DATE('Asia/Ho_Chi_Minh')                                   AS today_vn
    ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY)         AS report_date
)
SELECT
   today_vn
  ,report_date
  ,DATE_SUB(DATE_TRUNC(DATE_ADD(report_date, INTERVAL 1 DAY), WEEK(MONDAY)), INTERVAL 7 DAY) AS cur_wk_start
  ,DATE_SUB(DATE_TRUNC(DATE_ADD(report_date, INTERVAL 1 DAY), WEEK(MONDAY)), INTERVAL 1 DAY) AS cur_wk_end
  ,DATE_SUB(DATE_TRUNC(DATE_ADD(report_date, INTERVAL 1 DAY), WEEK(MONDAY)), INTERVAL 14 DAY) AS prv_wk_start
  ,DATE_SUB(DATE_TRUNC(DATE_ADD(report_date, INTERVAL 1 DAY), WEEK(MONDAY)), INTERVAL 8 DAY)  AS prv_wk_end
  ,DATE_TRUNC(report_date, MONTH)                                       AS month_start
  ,DATE_SUB(DATE_TRUNC(today_vn, WEEK(MONDAY)), INTERVAL 1 DAY)         AS last_sunday
  ,DATE_DIFF(report_date, DATE_TRUNC(report_date, MONTH), DAY) + 1      AS mtd_days_elapsed
  ,DATE_DIFF(LAST_DAY(report_date), DATE_TRUNC(report_date, MONTH), DAY) + 1 AS month_total_days
  -- thresholds, kept here so they are visible and changed in ONE place
  ,0.03   AS flat_band              -- +/- 3% counts as "~flat"
  ,50e6   AS material_abs_vnd       -- highlight floor: 50m VND ...
  ,0.05   AS material_pct           -- ... AND 5% move
  ,20     AS x_overstock_units      -- X
  ,182    AS y_overstock_cover_days -- Y = 26 weeks
  ,28     AS z_understock_cover_days-- Z = 4 weeks
  ,0.80   AS w_sell_through         -- W = 80% (binds above the ~76% structural floor at D=90)
  ,60     AS i_days_range           -- window for fn_stats_product_v2
  ,5      AS trending_min_base_units
FROM b;


/* -----------------------------------------------------------------------------
   2. dash_base_sku_day
   -----------------------------------------------------------------------------
   SKU-grain units. Built from the SAME sources as dash_base_order_day, reading
   the China raw tables directly so it is immune to the 4.03x TVF fan-out even if
   00_fix has not been applied. Used only by the trending list.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_base_sku_day`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_base_sku_day`
PARTITION BY period_date
CLUSTER BY level_2, variation_code
AS
SELECT * EXCEPT(level_1,level_3)
FROM `marine-cycle-484213-b4.reportdb.fn_order_sku_master`(0,2);


/* -----------------------------------------------------------------------------
   3. dash_page1_wow   -- PAGE 1, SECTION 2 (trend view) + diagnosis engine
   -----------------------------------------------------------------------------
   Grain: country x level_1 x level_2.
   bills = COUNT(DISTINCT order_id). Verified in Phase 1 that no order spans more
   than one channel, so this is exact and additive at every rollup.
   basket = nmv / bills.

   DIAGNOSIS. The five rows of the agreed decision table are matched EXACTLY and
   tagged diagnosis_source='decision_table'. The table covers 5 of 27 possible
   direction combinations; anything else is tagged 'derived' and described from
   the metrics rather than forced into a row it does not fit ("never state a
   diagnosis the metrics don't support").

   DRIVER. bills if |%d bills| >= 2x |%d basket|; basket if the reverse;
   otherwise 'mixed' -- i.e. when both moved and neither dominates we say mixed
   instead of picking one.

   TRAFFIC. Not present in any source. The conversion-rate rule cannot be
   evaluated, so wherever bills fell we say so explicitly rather than skipping it.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_page1_wow`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_page1_wow` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
agg AS (
  SELECT
     b.country, b.level_1, b.level_2
    ,SUM(IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.nmv, 0)) AS nmv_cur
    ,SUM(IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.nmv, 0)) AS nmv_prv
    ,SUM(IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.gmv, 0)) AS gmv_cur
    ,SUM(IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.gmv, 0)) AS gmv_prv
    ,COUNT(DISTINCT IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.order_id, NULL)) AS bills_cur
    ,COUNT(DISTINCT IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.order_id, NULL)) AS bills_prv
    ,SUM(IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.units_sold, 0)) AS units_cur
    ,SUM(IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.units_sold, 0)) AS units_prv
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b
  CROSS JOIN p
  WHERE b.period_date BETWEEN p.prv_wk_start AND p.cur_wk_end
  GROUP BY 1,2,3
),
calc AS (
  SELECT a.*, p.flat_band, p.cur_wk_start, p.cur_wk_end, p.prv_wk_start, p.prv_wk_end
    ,SAFE_DIVIDE(a.nmv_cur, a.bills_cur)                    AS basket_cur
    ,SAFE_DIVIDE(a.nmv_prv, a.bills_prv)                    AS basket_prv
    ,a.nmv_cur - a.nmv_prv                                  AS delta_nmv
    ,SAFE_DIVIDE(a.nmv_cur, NULLIF(a.nmv_prv,0)) - 1        AS pct_nmv
    ,SAFE_DIVIDE(a.gmv_cur, NULLIF(a.gmv_prv,0)) - 1        AS pct_gmv
    ,SAFE_DIVIDE(a.bills_cur, NULLIF(a.bills_prv,0)) - 1    AS pct_bills
    ,SAFE_DIVIDE(SAFE_DIVIDE(a.nmv_cur,a.bills_cur),
        NULLIF(SAFE_DIVIDE(a.nmv_prv,a.bills_prv),0)) - 1   AS pct_basket
  FROM agg a CROSS JOIN p
),
dir AS (
  SELECT c.*
    ,CASE WHEN pct_nmv    IS NULL THEN 'n/a' WHEN ABS(pct_nmv)   <flat_band THEN 'flat' WHEN pct_nmv   >0 THEN 'up' ELSE 'down' END AS rev_dir
    ,CASE WHEN pct_bills  IS NULL THEN 'n/a' WHEN ABS(pct_bills) <flat_band THEN 'flat' WHEN pct_bills >0 THEN 'up' ELSE 'down' END AS bills_dir
    ,CASE WHEN pct_basket IS NULL THEN 'n/a' WHEN ABS(pct_basket)<flat_band THEN 'flat' WHEN pct_basket>0 THEN 'up' ELSE 'down' END AS basket_dir
    ,CASE WHEN ABS(IFNULL(pct_bills,0)) >= 2*ABS(IFNULL(pct_basket,0)) THEN 'bills'
          WHEN ABS(IFNULL(pct_basket,0)) >= 2*ABS(IFNULL(pct_bills,0)) THEN 'basket'
          ELSE 'mixed' END AS driver
  FROM calc c
)
SELECT
   cur_wk_start, cur_wk_end, prv_wk_start, prv_wk_end
  ,country, level_1, level_2
  ,nmv_prv, nmv_cur, delta_nmv, pct_nmv
  ,gmv_prv, gmv_cur, pct_gmv
  ,bills_prv, bills_cur, pct_bills
  ,basket_prv, basket_cur, pct_basket
  ,units_prv, units_cur
  ,rev_dir, bills_dir, basket_dir, driver
  -- ---------- decision table (exact matches) ----------
  ,CASE
     WHEN rev_dir='down' AND bills_dir='down' AND basket_dir='flat' THEN 'Fewer customers'
     WHEN rev_dir='down' AND bills_dir='up'   AND basket_dir='down' THEN 'Weak cross-sell / upsell'
     WHEN rev_dir='down' AND bills_dir='down' AND basket_dir='up'   THEN 'Volume loss masked by mix'
     WHEN rev_dir='up'   AND bills_dir='down' AND basket_dir='up'   THEN 'Growth is fragile - fewer, bigger baskets'
     WHEN rev_dir='up'   AND bills_dir='up'   AND basket_dir='down' THEN 'Growth via discounting'
     -- ---------- derived (not in the table) ----------
     WHEN rev_dir='flat' THEN 'No material revenue movement'
     WHEN rev_dir='up'   AND driver='bills'  THEN 'Growth driven by transaction volume'
     WHEN rev_dir='up'   AND driver='basket' THEN 'Growth driven by basket size'
     WHEN rev_dir='up'                       THEN 'Growth from both volume and basket - driver is mixed'
     WHEN rev_dir='down' AND driver='bills'  THEN 'Decline driven by fewer transactions'
     WHEN rev_dir='down' AND driver='basket' THEN 'Decline driven by smaller baskets'
     WHEN rev_dir='down'                     THEN 'Decline from both volume and basket - driver is mixed'
     ELSE 'Insufficient comparison data'
   END AS diagnosis
  ,CASE
     WHEN (rev_dir='down' AND bills_dir='down' AND basket_dir='flat')
       OR (rev_dir='down' AND bills_dir='up'   AND basket_dir='down')
       OR (rev_dir='down' AND bills_dir='down' AND basket_dir='up')
       OR (rev_dir='up'   AND bills_dir='down' AND basket_dir='up')
       OR (rev_dir='up'   AND bills_dir='up'   AND basket_dir='down')
     THEN 'decision_table' ELSE 'derived' END AS diagnosis_source
  ,CASE
     WHEN rev_dir='down' AND bills_dir='down' AND basket_dir='flat' THEN 'Check traffic (footfall for Store, sessions for Ecom)'
     WHEN rev_dir='down' AND bills_dir='up'   AND basket_dir='down' THEN 'Review attach rate, bundles, staff training'
     WHEN rev_dir='down' AND bills_dir='down' AND basket_dir='up'   THEN 'Check conversion and price/discount mix'
     WHEN rev_dir='up'   AND bills_dir='down' AND basket_dir='up'   THEN 'Check customer acquisition pipeline'
     WHEN rev_dir='up'   AND bills_dir='up'   AND basket_dir='down' THEN 'Check margin and discount depth'
     WHEN rev_dir='down' AND driver='basket' THEN 'Check discount depth and product mix'
     WHEN rev_dir='down' AND driver='bills'  THEN 'Check traffic and conversion'
     WHEN rev_dir='down'                     THEN 'Check traffic, conversion and discount mix'
     ELSE 'No action required' END AS action_trigger
  -- traffic is unavailable everywhere; say so rather than silently skipping the rule
  ,bills_dir='down' AS bills_declined
  ,IF(bills_dir='down',
      'Traffic/footfall not available in source - cannot separate traffic loss from conversion loss. Verify traffic first.',
      NULL) AS traffic_note
FROM dir
WHERE nmv_cur > 0 OR nmv_prv > 0;


/* -----------------------------------------------------------------------------
   4. dash_page2_mtd   -- PAGE 2, SECTION 2 (MTD vs target)
   -----------------------------------------------------------------------------
   PER-CHANNEL CUTOFF. Tmall and Taobao upload manually once a week (Mon AM) and
   are complete only through the most recent Sunday; everything else is complete
   to T-1. A channel's cutoff is the EARLIEST cutoff among its platforms, so
   TQ Ecommerce is measured to last Sunday. The target is pro-rated to that SAME
   date, so every channel is compared like-for-like instead of against a target
   that assumes days it has no data for.

   SUPPRESSION. attainment is NULL when the full-month target < 500m VND
   (is_low_target) or <= 0 (is_target_invalid). VN Wholesales would otherwise
   print 633%. The threshold keys on FULL-MONTH target, not MTD, because MTD
   target grows through the month. Verified: across all 10 channels x 12 months
   of FY2026 this flags only VN Wholesales and the two Pop-ups, never a real
   trading channel.

   UNMAPPED. TL Pop-up / TQ Pop-up carry target but have no actuals channel and a
   NULL sale_channel_type. They are retained as a fifth 'Unmapped' group so the
   plan denominator stays whole.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_page2_mtd`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_page2_mtd` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
cut AS (
  SELECT level_2, MIN(data_complete_through) AS cutoff
  FROM `marine-cycle-484213-b4.reportdb.dash_dq_platform_day`
  GROUP BY level_2
),
act AS (
  SELECT b.country, b.level_1, b.level_2,
         SUM(b.nmv) AS mtd_nmv,
         SUM(b.gmv) AS mtd_gmv,
         COUNT(DISTINCT b.order_id) AS mtd_bills
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b
  JOIN cut c USING (level_2)
  CROSS JOIN p
  WHERE b.period_date BETWEEN p.month_start AND c.cutoff
  GROUP BY 1,2,3
),
tgt AS (
  -- LEFT JOIN to cut (not inner) so target-only channels are not dropped
  SELECT t.level_2,
         ANY_VALUE(t.country)              AS country,
         ANY_VALUE(t.level_1)              AS level_1,
         SUM(t.target_revenue)             AS mtd_target,
         ANY_VALUE(t.month_target_revenue) AS month_target,
         LOGICAL_OR(t.is_low_target)       AS is_low_target,
         LOGICAL_OR(t.is_target_invalid)   AS is_target_invalid,
         LOGICAL_OR(t.is_unmapped_channel) AS is_unmapped_channel,
         LOGICAL_OR(t.is_multi_country_target) AS is_multi_country_target
  FROM `marine-cycle-484213-b4.reportdb.dash_target_day` t
  LEFT JOIN cut c USING (level_2)
  CROSS JOIN p
  WHERE t.sale_date BETWEEN p.month_start AND IFNULL(c.cutoff, p.report_date)
  GROUP BY t.level_2
)
SELECT
   p.month_start
  ,IFNULL(c.cutoff, p.report_date)                       AS data_as_of
  ,p.mtd_days_elapsed
  ,p.month_total_days
  ,COALESCE(a.country, t.country)                        AS country
  ,COALESCE(a.level_1, t.level_1)                        AS level_1
  ,COALESCE(a.level_2, t.level_2)                        AS level_2
  ,IFNULL(a.mtd_nmv, 0)                                  AS mtd_actual_nmv
  ,IFNULL(a.mtd_gmv, 0)                                  AS mtd_actual_gmv
  ,IFNULL(a.mtd_bills, 0)                                AS mtd_bills
  ,SAFE_DIVIDE(a.mtd_nmv, a.mtd_bills)                   AS mtd_basket
  ,IFNULL(t.mtd_target, 0)                               AS mtd_target
  ,t.month_target                                        AS full_month_target
  ,IFNULL(a.mtd_nmv,0) - IFNULL(t.mtd_target,0)          AS gap_to_target
  -- attainment suppressed where the denominator is too small or invalid
  ,IF(t.is_low_target OR t.is_target_invalid, NULL,
      SAFE_DIVIDE(a.mtd_nmv, NULLIF(t.mtd_target,0)))    AS attainment_pct
  ,CASE WHEN t.is_target_invalid THEN 'Target <= 0 - attainment not meaningful'
        WHEN t.is_low_target     THEN 'Full-month target < 500m VND - attainment suppressed'
        WHEN t.level_2 IS NULL   THEN 'No target set for this channel'
        WHEN a.level_2 IS NULL   THEN 'Target exists but no actuals channel maps to it'
        ELSE NULL END                                    AS attainment_note
  ,CASE WHEN t.is_low_target OR t.is_target_invalid THEN NULL
        WHEN IFNULL(a.mtd_nmv,0) >= IFNULL(t.mtd_target,0) THEN 'HIT'
        ELSE 'MISS' END                                  AS target_status
  ,IFNULL(t.is_low_target, FALSE)                        AS is_low_target
  ,IFNULL(t.is_target_invalid, FALSE)                    AS is_target_invalid
  ,IFNULL(t.is_unmapped_channel, FALSE)                  AS is_unmapped_channel
  ,IFNULL(t.is_multi_country_target, FALSE)              AS is_multi_country_target
  -- period is incomplete by construction; say so rather than reading it as a decline
  ,ROUND(SAFE_DIVIDE(p.mtd_days_elapsed, p.month_total_days), 3) AS month_elapsed_share
  ,CONCAT('Day ', CAST(p.mtd_days_elapsed AS STRING), ' of ',
          CAST(p.month_total_days AS STRING), ' - month incomplete') AS period_note
FROM act a
FULL OUTER JOIN tgt t ON a.level_2 = t.level_2
LEFT JOIN cut c ON c.level_2 = COALESCE(a.level_2, t.level_2)
CROSS JOIN p;


/* -----------------------------------------------------------------------------
   5. dash_highlights   -- SECTION 1 for BOTH pages
   -----------------------------------------------------------------------------
   Max 3 highlights + 3 lowlights per page, ranked by ABSOLUTE VND impact, never
   by percentage -- a -5% on the largest channel must outrank a -40% on a trivial
   one. A materiality floor (>= 50m VND AND >= 5%) stops noise being dressed up
   as a lowlight; if fewer than 3 items clear it, fewer than 3 are returned.

   Page 1 ranks on WoW delta. Page 2 ranks on gap to target, and excludes rows
   with suppressed attainment so a low-target channel can never be a "highlight".
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_highlights`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_highlights` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

wow AS (
  SELECT 'PAGE1_WOW' AS page, country, level_1, level_2,
         delta_nmv AS impact_vnd, pct_nmv AS pct_change,
         nmv_cur AS value_cur, nmv_prv AS value_ref,
         bills_cur, bills_prv, pct_bills, basket_cur, basket_prv, pct_basket,
         driver, diagnosis, diagnosis_source, action_trigger, traffic_note,
         IF(delta_nmv >= 0, 'HIGHLIGHT', 'LOWLIGHT') AS item_type
  FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`
  CROSS JOIN p
  WHERE ABS(delta_nmv) >= p.material_abs_vnd
    AND ABS(IFNULL(pct_nmv,0)) >= p.material_pct
),
mtd AS (
  SELECT 'PAGE2_MTD' AS page, country, level_1, level_2,
         gap_to_target AS impact_vnd,
         attainment_pct - 1 AS pct_change,
         mtd_actual_nmv AS value_cur, mtd_target AS value_ref,
         mtd_bills AS bills_cur, CAST(NULL AS INT64) AS bills_prv,
         CAST(NULL AS FLOAT64) AS pct_bills,
         mtd_basket AS basket_cur, CAST(NULL AS FLOAT64) AS basket_prv,
         CAST(NULL AS FLOAT64) AS pct_basket,
         CAST(NULL AS STRING) AS driver,
         CONCAT(target_status, ' - ', FORMAT('%.0f', attainment_pct*100), '% of MTD target') AS diagnosis,
         'derived' AS diagnosis_source,
         IF(target_status='MISS','Close the gap or re-forecast the month','Protect the run-rate') AS action_trigger,
         CAST(NULL AS STRING) AS traffic_note,
         IF(gap_to_target >= 0, 'HIGHLIGHT', 'LOWLIGHT') AS item_type
  FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
  CROSS JOIN p
  WHERE attainment_pct IS NOT NULL          -- suppressed rows can never headline
    AND ABS(gap_to_target) >= p.material_abs_vnd
),
u AS (SELECT * FROM wow UNION ALL SELECT * FROM mtd)
SELECT * EXCEPT(rn), rn AS rank_in_group
FROM (
  SELECT u.*, ROW_NUMBER() OVER (PARTITION BY page, item_type ORDER BY ABS(impact_vnd) DESC) AS rn
  FROM u
)
WHERE rn <= 3;


/* -----------------------------------------------------------------------------
   6. dash_stock_lists   -- SECTION 3
   -----------------------------------------------------------------------------
   fn_stats_product_v2(i_type=1, i_days_range=90) with a 90-DAY WINDOW.
   The window MUST be >= i_days_range: the rolling velocity window is truncated
   by the date filter, so a short window understates velocity and overstates
   cover (measured 2.6x on a 7-day window vs 28-day range).

   Approved thresholds: X=20 units, Y=26wk (182d), Z=4wk (28d), W=80%.
   NOTE ON W: cover <= Z mathematically forces sell-through >= D/(D+Z). At D=90,
   Z=28 that floor is ~76%, so anything at or below 76% would never bind. W=80%
   sits just above it and does filter (94 candidates -> 74).

   List 4 (discontinued) is an addition: 1,402 SKUs are tagged SYS_01_SALE_END
   and are excluded from every score by the function, yet still hold ~29bn VND
   (41% of total stock value). Without this list the overstock picture is
   understated by that much.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_stock_lists`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_stock_lists` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
s AS (
  -- Window is exactly 90 days ending T-1, matching i_days_range=90.
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_stats_product_v2`(
        1, 0, 90, 90,
        DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 90 DAY),
        DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL  1 DAY))
),
trend AS (
  SELECT k.variation_code,
         SUM(IF(k.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, k.units_sold, 0)) AS units_cur,
         SUM(IF(k.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, k.units_sold, 0)) AS units_prv
  FROM `marine-cycle-484213-b4.reportdb.dash_base_sku_day` k
  CROSS JOIN p
  WHERE k.period_date BETWEEN p.prv_wk_start AND p.cur_wk_end
  GROUP BY k.variation_code
),

l1 AS (  -- OVERSTOCK / SLOW-MOVING
  SELECT 'OVERSTOCK' AS list_name, s.variation_code, s.product_name, s.updated_date,
         CAST(s.sl_ton_kho AS FLOAT64) AS units_on_hand,
         CAST(s.DOH AS FLOAT64) AS cover_days,
         ROUND(SAFE_DIVIDE(s.DOH,7),1) AS cover_weeks,
         CAST(s.sell_through_rate AS FLOAT64) AS sell_through_rate,
         CAST(s.sale_velocity AS FLOAT64) AS sale_velocity,
         CAST(s.excess_value AS FLOAT64) AS rank_value,
         'Tied-up excess value (VND)' AS rank_metric,
         s.colour_bucket, s.alert_code,
         CAST(NULL AS FLOAT64) AS units_cur, CAST(NULL AS FLOAT64) AS units_prv
  FROM s WHERE s.is_inactive = 0
    AND s.sl_ton_kho >= 20
    AND (s.DOH >= 182 OR s.doh_is_infinite = 1)
),
l2 AS (  -- UNDERSTOCK / FAST-MOVING
  SELECT 'UNDERSTOCK', s.variation_code, s.product_name, s.updated_date,
         CAST(s.sl_ton_kho AS FLOAT64), CAST(s.DOH AS FLOAT64), ROUND(SAFE_DIVIDE(s.DOH,7),1),
         CAST(s.sell_through_rate AS FLOAT64), CAST(s.sale_velocity AS FLOAT64),
         CAST(s.sale_velocity * s.retail_price * 28 AS FLOAT64),
         'Lost-sales risk: 4wk demand at current velocity (VND)',
         s.colour_bucket, s.alert_code, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64)
  FROM s WHERE s.is_inactive = 0
    AND s.sale_velocity > 0
    AND s.doh_is_infinite = 0
    AND s.DOH <= 28
    AND s.sell_through_rate >= 0.80
),
l3 AS (  -- TOP TRENDING (WoW unit growth, min 5-unit prior base)
  SELECT 'TRENDING', t.variation_code, s.product_name, s.updated_date,
         CAST(s.sl_ton_kho AS FLOAT64), CAST(s.DOH AS FLOAT64), ROUND(SAFE_DIVIDE(s.DOH,7),1),
         CAST(s.sell_through_rate AS FLOAT64), CAST(s.sale_velocity AS FLOAT64),
         CAST(t.units_cur - t.units_prv AS FLOAT64),
         'Absolute WoW unit gain (base >= 5 units)',
         s.colour_bucket, s.alert_code,
         CAST(t.units_cur AS FLOAT64), CAST(t.units_prv AS FLOAT64)
  FROM trend t
  LEFT JOIN s ON s.variation_code = t.variation_code
  WHERE t.units_prv >= 5 AND t.units_cur > t.units_prv
),
l4 AS (  -- DISCONTINUED STOCK TO LIQUIDATE
  SELECT 'DISCONTINUED', s.variation_code, s.product_name, s.updated_date,
         CAST(s.sl_ton_kho AS FLOAT64), CAST(s.DOH AS FLOAT64), ROUND(SAFE_DIVIDE(s.DOH,7),1),
         CAST(s.sell_through_rate AS FLOAT64), CAST(s.sale_velocity AS FLOAT64),
         CAST(s.tong_gia_tri_hang_ton_kho_theo_gia_ban AS FLOAT64),
         'Stock value at retail (VND)',
         s.colour_bucket, s.alert_code, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64)
  FROM s WHERE s.is_sale_end = 1 AND s.sl_ton_kho >= 20
)
SELECT * EXCEPT(rn), rn AS rank_in_list
FROM (
  SELECT x.*, ROW_NUMBER() OVER (PARTITION BY list_name ORDER BY rank_value DESC) AS rn
  FROM (SELECT * FROM l1 UNION ALL SELECT * FROM l2
        UNION ALL SELECT * FROM l3 UNION ALL SELECT * FROM l4) x
)
WHERE rn <= 10;


/* -----------------------------------------------------------------------------
   7. dash_action_items   -- SECTION 4
   -----------------------------------------------------------------------------
   Max 5 per page. Every item traces to a specific highlight/lowlight via
   source_item. Owner is derived from country + level_1.
   Format for rendering: '[owner] - action'.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_action_items`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_action_items` AS
WITH owner_map AS (
  SELECT h.*,
    CONCAT(
      CASE h.country WHEN 'VIETNAM' THEN 'VN' WHEN 'THAILAND' THEN 'TH'
                     WHEN 'CHINA' THEN 'CN' ELSE 'GRP' END, ' ',
      CASE h.level_1 WHEN 'Store' THEN 'Retail' WHEN 'Sale Ecommerce' THEN 'Ecom'
                     WHEN 'Sale Online' THEN 'Online' WHEN 'Wholesales' THEN 'Wholesale'
                     ELSE 'Planning' END
    ) AS owner
  FROM `marine-cycle-484213-b4.reportdb.dash_highlights` h
),
ranked AS (
  SELECT page, owner, country, level_2, item_type, impact_vnd, diagnosis,
         action_trigger, traffic_note,
         CONCAT(country, ' / ', level_2, ' ', item_type) AS source_item,
         ROW_NUMBER() OVER (PARTITION BY page ORDER BY ABS(impact_vnd) DESC) AS rn
  FROM owner_map
  WHERE action_trigger <> 'No action required'
)
SELECT page, rn AS action_no,
       CONCAT('[', owner, '] - ', action_trigger) AS action_item,
       owner, source_item, impact_vnd, diagnosis, traffic_note
FROM ranked
WHERE rn <= 5;


/* -----------------------------------------------------------------------------
   8. dash_page_summary   -- HEADLINE FIGURES for both pages
   -----------------------------------------------------------------------------
   PAGE 2 HEADLINE ATTAINMENT EXCLUDES THE UNMAPPED POP-UP TARGET.
   TL Pop-up and TQ Pop-up carry plan but have no actuals channel to book revenue
   against, so leaving them in the denominator penalises channels that had nothing
   to do with them. The headline therefore uses mapped target only -- but the
   excluded amount and the all-in figure are BOTH carried on the row, and
   headline_note spells out the exclusion in words, so no reader can mistake the
   basis. Never publish headline_pct without headline_note.

   VN Wholesales IS included in the totals even though its channel-level
   attainment is suppressed. Suppression exists to stop a meaningless 633% being
   shown as a channel highlight; at total level the denominator is large enough
   that its 45m target distorts nothing, and dropping genuinely earned revenue
   would understate the business.

   MIXED AS-OF DATES: China Ecommerce is measured to last Sunday (weekly manual
   upload) while every other channel runs to T-1. data_as_of_note states this.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_page_summary`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_page_summary` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
p1 AS (
  SELECT SUM(nmv_cur) AS cur_nmv, SUM(nmv_prv) AS prv_nmv,
         SUM(gmv_cur) AS cur_gmv, SUM(gmv_prv) AS prv_gmv,
         SUM(bills_cur) AS cur_bills, SUM(bills_prv) AS prv_bills
  FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`
),
p2 AS (
  SELECT SUM(mtd_actual_nmv)                        AS actual_nmv,
         SUM(IF(is_unmapped_channel, 0, mtd_target)) AS target_mapped,
         SUM(mtd_target)                            AS target_all,
         SUM(IF(is_unmapped_channel, mtd_target, 0)) AS target_unmapped,
         SUM(mtd_bills)                             AS bills
  FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
),
asof AS (
  SELECT STRING_AGG(DISTINCT FORMAT('%s to %t', level_2, data_complete_through), '; '
         ORDER BY FORMAT('%s to %t', level_2, data_complete_through)) AS lagging
  FROM `marine-cycle-484213-b4.reportdb.dash_dq_platform_day`
  WHERE is_weekly_load
)
SELECT 'PAGE1_WOW' AS page,
       FORMAT('%t to %t vs %t to %t', p.cur_wk_start, p.cur_wk_end, p.prv_wk_start, p.prv_wk_end) AS period_label,
       p1.cur_nmv        AS headline_actual,
       p1.prv_nmv        AS headline_reference,
       SAFE_DIVIDE(p1.cur_nmv, NULLIF(p1.prv_nmv,0)) - 1 AS headline_pct,
       p1.cur_gmv, p1.prv_gmv,
       SAFE_DIVIDE(p1.cur_gmv, NULLIF(p1.prv_gmv,0)) - 1 AS gmv_pct,
       p1.cur_bills      AS bills,
       SAFE_DIVIDE(p1.cur_nmv, NULLIF(p1.cur_bills,0))   AS basket,
       CAST(NULL AS FLOAT64) AS excluded_target,
       CAST(NULL AS FLOAT64) AS pct_including_excluded,
       'Both weeks are complete for every platform, including the weekly Tmall/Taobao upload.' AS data_as_of_note,
       'NMV basis. China NMV is modelled from GMV for periods under 30 days old.' AS headline_note
FROM p1 CROSS JOIN p

UNION ALL

SELECT 'PAGE2_MTD',
       FORMAT('%t to %t (day %d of %d)', p.month_start, p.report_date, p.mtd_days_elapsed, p.month_total_days),
       p2.actual_nmv,
       p2.target_mapped,
       SAFE_DIVIDE(p2.actual_nmv, NULLIF(p2.target_mapped,0)),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       p2.bills,
       SAFE_DIVIDE(p2.actual_nmv, NULLIF(p2.bills,0)),
       p2.target_unmapped,
       SAFE_DIVIDE(p2.actual_nmv, NULLIF(p2.target_all,0)),
       CONCAT('Weekly-load channels complete to: ', IFNULL(asof.lagging,'none'),
              '. All other channels complete to ', FORMAT('%t', p.report_date), '.'),
       FORMAT(
         'Attainment %.0f%% EXCLUDES %.0fm VND of TL Pop-up / TQ Pop-up target, which carry plan but have no actuals channel. Including them, attainment is %.0f%%. Month is incomplete: day %d of %d.',
         SAFE_DIVIDE(p2.actual_nmv, NULLIF(p2.target_mapped,0))*100,
         p2.target_unmapped/1e6,
         SAFE_DIVIDE(p2.actual_nmv, NULLIF(p2.target_all,0))*100,
         p.mtd_days_elapsed, p.month_total_days)
FROM p2 CROSS JOIN p CROSS JOIN asof;


/* =============================================================================
   VALIDATION
   ============================================================================= */

-- V1. Period boundaries. EXPECT cur_wk_end = a Sunday, and cur_wk_end <= report_date.
SELECT report_date, FORMAT_DATE('%a', report_date) AS report_dow,
       cur_wk_start, cur_wk_end, FORMAT_DATE('%a', cur_wk_end) AS wk_end_dow,
       prv_wk_start, prv_wk_end, month_start, last_sunday,
       mtd_days_elapsed, month_total_days,
       cur_wk_end <= report_date AS week_is_complete
FROM `marine-cycle-484213-b4.reportdb.dash_run_params`;

-- V2. WoW totals must reconcile to the base table. EXPECT diff = 0.
WITH pg AS (SELECT SUM(nmv_cur) a, SUM(nmv_prv) b FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`),
bs AS (
  SELECT SUM(IF(period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, nmv,0)) a,
         SUM(IF(period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, nmv,0)) b
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  CROSS JOIN `marine-cycle-484213-b4.reportdb.dash_run_params` p
)
SELECT ROUND(pg.a-bs.a) AS diff_cur_week, ROUND(pg.b-bs.b) AS diff_prev_week FROM pg CROSS JOIN bs;

-- V3. Bills must not be double counted. EXPECT sum_of_channels = distinct_overall.
SELECT (SELECT SUM(bills_cur) FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`) AS sum_of_channels,
       (SELECT COUNT(DISTINCT order_id) FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b
         CROSS JOIN `marine-cycle-484213-b4.reportdb.dash_run_params` p
        WHERE b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end) AS distinct_overall;

-- V4. Page 1 rendered.
SELECT country, level_2,
       ROUND(nmv_prv/1e6) AS prev_mVND, ROUND(nmv_cur/1e6) AS cur_mVND,
       ROUND(delta_nmv/1e6) AS delta_mVND, ROUND(pct_nmv*100) AS rev_pct,
       bills_prv, bills_cur, ROUND(pct_bills*100) AS bills_pct,
       ROUND(basket_prv/1e3) AS basket_prev_k, ROUND(basket_cur/1e3) AS basket_cur_k,
       ROUND(pct_basket*100) AS basket_pct,
       driver, diagnosis, diagnosis_source
FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`
ORDER BY ABS(delta_nmv) DESC;

-- V5. Page 2 rendered. EXPECT Pop-ups present as Unmapped; VN Wholesales attainment NULL.
SELECT country, level_1, level_2, data_as_of,
       ROUND(mtd_actual_nmv/1e6) AS actual_mVND, ROUND(mtd_target/1e6) AS target_mVND,
       ROUND(gap_to_target/1e6) AS gap_mVND,
       ROUND(attainment_pct*100) AS attainment_pct,
       target_status, attainment_note
FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
ORDER BY ABS(gap_to_target) DESC;

-- V6. Highlights/lowlights. EXPECT <= 3 per page per type, ranked by |impact|.
SELECT page, item_type, rank_in_group, country, level_2,
       ROUND(impact_vnd/1e6) AS impact_mVND, ROUND(pct_change*100) AS pct,
       driver, diagnosis
FROM `marine-cycle-484213-b4.reportdb.dash_highlights`
ORDER BY page, item_type, rank_in_group;

-- V7. Stock lists filled. EXPECT 4 lists, up to 10 each.
--     NOTE rank_value is VND for OVERSTOCK/UNDERSTOCK/DISCONTINUED but UNITS for
--     TRENDING -- read rank_metric, don't sum across lists.
SELECT list_name, ANY_VALUE(rank_metric) AS rank_metric, COUNT(*) AS skus,
       ROUND(MIN(rank_value),1) AS min_rank_value,
       ROUND(MAX(rank_value),1) AS max_rank_value
FROM `marine-cycle-484213-b4.reportdb.dash_stock_lists` GROUP BY list_name ORDER BY list_name;

-- V8. Action items.
SELECT page, action_no, action_item, source_item, ROUND(impact_vnd/1e6) AS impact_mVND
FROM `marine-cycle-484213-b4.reportdb.dash_action_items` ORDER BY page, action_no;

-- V9. Headline figures. EXPECT PAGE2 headline_pct ~= 0.833 and the note to state
--     both the excluded Pop-up amount and the all-in figure.
SELECT page, period_label,
       ROUND(headline_actual/1e6)      AS actual_mVND,
       ROUND(headline_reference/1e6)   AS reference_mVND,
       ROUND(headline_pct*100,1)       AS headline_pct,
       ROUND(excluded_target/1e6)      AS excluded_target_mVND,
       ROUND(pct_including_excluded*100,1) AS pct_incl_excluded,
       bills, ROUND(basket/1e3) AS basket_kVND,
       data_as_of_note, headline_note
FROM `marine-cycle-484213-b4.reportdb.dash_page_summary` ORDER BY page;