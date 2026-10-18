/* =============================================================================
   LSOUL PERFORMANCE DASHBOARD  --  04: TREND SERIES + AI INSIGHT LAYER
   Run AFTER 03_actions_and_bilingual.sql.

   This file is the SINGLE owner of the AI layer. It merges what were previously
   two files (an English-only AI layer, then a trends/exec-summary extension that
   replaced most of it). Every object below is created exactly once.

   Creates:
     1. dash_trend_weekly        -- 8 complete weeks + current, by channel
     2. dash_trend_monthly       -- 6 months, attainment and pace
     3. dash_materiality_config  -- the thresholds, in one editable place
     4. dash_material_points     -- THE single filtered point set (consistency anchor)
     5. v_dash_ai_facts_core     -- prompt assembly (trend series + material points)
     6. dash_ai_narrative        -- cache: exec summary + bilingual narrative
     7. sp_dash_generate_ai      -- 2 model calls per refresh, 0 if unchanged
     8. v_dash_report            -- what the dashboard binds to
     9. v_dash_ai_cost           -- measured cost from stored token counts
    10. v_dash_consistency_check -- enforces "one narrative, four views"

   NOTE ON v_dash_ai_facts (no _core): created in 05_review_and_feedback.sql as a
   guidance-aware wrapper around v_dash_ai_facts_core. sp_dash_generate_ai reads
   the wrapper, so 05 must be run before the first generation. Run all six files
   in order and this resolves itself.

   ---------------------------------------------------------------------------
   ON THE BRIEF'S REQUEST TO "FEED IN v_dash_trend_page1 / page2"
   ---------------------------------------------------------------------------
   Those two views are CURRENT-PERIOD ONLY - page1 is current week vs prior week,
   page2 is MTD vs target. Neither holds 8 weeks or 6 months of history, so they
   cannot supply the series requested. They were also already reaching the model
   indirectly, since dash_highlights derives from the same underlying tables.
   This file therefore BUILDS the history; those views remain the section-2
   presentation layer, unchanged, in 03_actions_and_bilingual.sql.

   ---------------------------------------------------------------------------
   TWO DATA DEFECTS FOUND WHILE BUILDING THIS
   ---------------------------------------------------------------------------
   (1) NaN VALUES. SUM propagates NaN, so ONE bad row turns a channel-week into
       NaN, which turns MIN/MAX of the trailing 8 weeks into NaN, which makes the
       "outside trailing range" test silently return FALSE. A material movement
       would vanish with no error raised. Now fixed at source in 01_foundation.sql
       AND guarded again here, because a silent filter failure is worse than a
       redundant guard.
   (2) ZERO-VALUE ORDERS INFLATE BILLS AND DEFLATE AOV. Orders exist with zero or
       null revenue and zero units; they still count as a distinct bill. Measured,
       TQ Ecommerce week of 2026-08-03: 1,408 raw bills vs 1,309 with value - 99
       phantom bills (7%), pulling AOV from 857k down to 797k VND. A 7% AOV
       distortion is large when the materiality threshold is 15%. Bills here are
       counted only where nmv > 0.

   ---------------------------------------------------------------------------
   AOV vs BASKET SIZE
   ---------------------------------------------------------------------------
   The brief lists both. Under the master prompt's own definition - "Basket size
   (revenue / bills)" - they are the SAME number, so reporting both would be two
   columns of one metric. This file keeps aov (= basket value = nmv/bills) and
   adds units_per_bill (UPT = units/bills), which is genuinely independent: it
   separates "bigger baskets because of more items" from "bigger baskets because
   of higher prices". The decision table cannot distinguish those two without it.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. dash_trend_weekly  -- 8 complete weeks + current
   -----------------------------------------------------------------------------
   Grain: week_start x country x level_1 x level_2 x level_3.
   The trailing-range window deliberately EXCLUDES the current week
   (RANGE BETWEEN 56 PRECEDING AND 7 PRECEDING), otherwise the current value
   would be inside its own comparison range by construction and could never be
   flagged as an outlier.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
PARTITION BY week_start
CLUSTER BY country, level_2
AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
wk AS (
  SELECT
     DATE_TRUNC(b.period_date, WEEK(MONDAY)) AS week_start
    ,b.country, b.level_1, b.level_2, b.level_3
    ,SUM(IF(IS_NAN(b.nmv)        OR b.nmv        IS NULL, 0, b.nmv))        AS nmv
    ,SUM(IF(IS_NAN(b.gmv)        OR b.gmv        IS NULL, 0, b.gmv))        AS gmv
    ,SUM(IF(IS_NAN(b.units_sold) OR b.units_sold IS NULL, 0, b.units_sold)) AS units
    -- bills counted only where the order carried value (see defect 2)
    ,COUNT(DISTINCT IF(IFNULL(b.nmv,0) > 0, b.order_id, NULL))              AS bills
    ,COUNT(DISTINCT b.order_id)                                             AS bills_incl_zero
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b
  CROSS JOIN p
  WHERE b.period_date >= DATE_SUB(p.cur_wk_start, INTERVAL 8 WEEK)
    AND b.period_date <= p.cur_wk_end
  GROUP BY 1,2,3,4,5
),
m AS (
  SELECT *,
     SAFE_DIVIDE(nmv,   NULLIF(bills,0)) AS aov          -- = basket value
    ,SAFE_DIVIDE(units, NULLIF(bills,0)) AS units_per_bill
  FROM wk
)
SELECT
   m.*
  ,p.cur_wk_start
  ,m.week_start = p.cur_wk_start AS is_current_week
  ,MIN(m.nmv)   OVER w AS nmv_min_8wk
  ,MAX(m.nmv)   OVER w AS nmv_max_8wk
  ,AVG(m.nmv)   OVER w AS nmv_avg_8wk
  ,MIN(m.bills) OVER w AS bills_min_8wk
  ,MAX(m.bills) OVER w AS bills_max_8wk
  ,MIN(m.aov)   OVER w AS aov_min_8wk
  ,MAX(m.aov)   OVER w AS aov_max_8wk
  ,COUNT(*)     OVER w AS hist_weeks_available
FROM m CROSS JOIN p
WINDOW w AS (
  PARTITION BY m.country, m.level_2, m.level_3
  ORDER BY UNIX_DATE(m.week_start)
  RANGE BETWEEN 56 PRECEDING AND 7 PRECEDING
);


/* -----------------------------------------------------------------------------
   2. dash_trend_monthly  -- 6 months, attainment and pace
   -----------------------------------------------------------------------------
   pace_gap_pp is the heart of requirement 3's third rule.
     expected pace = days elapsed / days in month
     actual pace   = MTD actual / FULL-MONTH target
     pace_gap_pp   = (actual - expected) x 100
   For a COMPLETED month expected pace is 100%, so pace_gap_pp is simply
   attainment minus 100 - which keeps one comparable number across the series.
   ----------------------------------------------------------------------------- */
drop table if exists `marine-cycle-484213-b4.reportdb.dash_trend_monthly`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_trend_monthly` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
cut AS (
  SELECT level_2, MIN(data_complete_through) AS cutoff
  FROM `marine-cycle-484213-b4.reportdb.dash_dq_platform_day` GROUP BY level_2
),
act AS (
  SELECT
     DATE_TRUNC(b.period_date, MONTH) AS month_start
    ,b.country, b.level_1, b.level_2
    ,SUM(IF(IS_NAN(b.nmv) OR b.nmv IS NULL, 0, b.nmv))          AS nmv
    ,COUNT(DISTINCT IF(IFNULL(b.nmv,0) > 0, b.order_id, NULL))  AS bills
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b
  LEFT JOIN cut c ON c.level_2 = b.level_2
  CROSS JOIN p
  WHERE b.period_date >= DATE_SUB(DATE_TRUNC(p.report_date, MONTH), INTERVAL 5 MONTH)
    AND b.period_date <= IFNULL(c.cutoff, p.report_date)
  GROUP BY 1,2,3,4
),
tgt AS (
  SELECT DATE_TRUNC(t.sale_date, MONTH) AS month_start, t.country, t.level_2,
         SUM(t.target_revenue)             AS month_target,
         LOGICAL_OR(t.is_low_target)       AS is_low_target,
         LOGICAL_OR(t.is_target_invalid)   AS is_target_invalid,
         LOGICAL_OR(t.is_unmapped_channel) AS is_unmapped_channel
  FROM `marine-cycle-484213-b4.reportdb.dash_target_day` t CROSS JOIN p
  WHERE t.sale_date >= DATE_SUB(DATE_TRUNC(p.report_date, MONTH), INTERVAL 5 MONTH)
    AND t.sale_date <= LAST_DAY(p.report_date)
  GROUP BY 1,2,3
)
SELECT
   COALESCE(a.month_start, t.month_start)          AS month_start
  ,COALESCE(a.country, t.country)                  AS country
  ,a.level_1
  ,COALESCE(a.level_2, t.level_2)                  AS level_2
  ,IFNULL(a.nmv, 0)                                AS nmv
  ,IFNULL(a.bills, 0)                              AS bills
  ,t.month_target
  ,COALESCE(a.month_start, t.month_start) = DATE_TRUNC(p.report_date, MONTH) AS is_current_month
  -- attainment is always against the FULL-MONTH target, so the series is comparable
  ,IF(t.is_low_target OR t.is_target_invalid, NULL,
      SAFE_DIVIDE(a.nmv, NULLIF(t.month_target,0)))               AS attainment_vs_full_month
  ,IF(COALESCE(a.month_start, t.month_start) = DATE_TRUNC(p.report_date, MONTH),
      SAFE_DIVIDE(p.mtd_days_elapsed, p.month_total_days), 1.0)   AS expected_pace
  ,IF(t.is_low_target OR t.is_target_invalid, NULL,
      (SAFE_DIVIDE(a.nmv, NULLIF(t.month_target,0))
       - IF(COALESCE(a.month_start, t.month_start) = DATE_TRUNC(p.report_date, MONTH),
            SAFE_DIVIDE(p.mtd_days_elapsed, p.month_total_days), 1.0)) * 100) AS pace_gap_pp
  ,IFNULL(t.is_low_target, FALSE)       AS is_low_target
  ,IFNULL(t.is_target_invalid, FALSE)   AS is_target_invalid
  ,IFNULL(t.is_unmapped_channel, FALSE) AS is_unmapped_channel
FROM act a
FULL OUTER JOIN tgt t
  ON a.month_start = t.month_start AND a.country = t.country AND a.level_2 = t.level_2
CROSS JOIN p;


/* -----------------------------------------------------------------------------
   3. dash_material_points  -- THE single source of truth for consistency
   -----------------------------------------------------------------------------
   Requirement 4 says one narrative across four views. That only holds if the set
   of points is decided ONCE, in SQL, and every field draws from the same set.
   This table is that set. exec_summary, highlights, lowlights, trends and actions
   all reference these point_ids, so a point cannot appear in one field and be
   missing from another.

   THRESHOLDS, exactly as specified:
     R1  WoW change >= +/-15% on nmv, bills or aov
     R2  metric outside the trailing 8-week range
     R3  pace off by >= 10pp

   R4 IS AN ADDITION, AND IT IS ON BY DEFAULT - read this before trusting the output.
   Applying R1-R3 literally to the live week SUPPRESSES the largest decline on the
   page. VN Offline Store moved -14% NMV, -2% bills, -12% AOV, all inside the 15%
   band and inside its 8-week range, with pace +5pp. Strictly it is immaterial.
   It is also -216m VND, the biggest absolute mover of the week.
   Meanwhile TL Offline Store at +12m VND (+4%) IS material under R2, because it
   edged above its 8-week range.
   So a literal reading sends the BOD a +12m item and hides a -216m one.
   R4 therefore admits the top N movers by absolute VND regardless of percentage.
   Set p_enable_abs_rule = FALSE in dash_materiality_config for literal compliance.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_materiality_config` AS
SELECT
   0.15  AS pct_threshold        -- R1
  ,10.0  AS pace_threshold_pp    -- R3
  ,TRUE  AS p_enable_abs_rule    -- R4 on/off
  ,2     AS abs_rule_top_n       -- how many absolute movers R4 admits per page
  ,50e6  AS abs_rule_min_vnd     -- and they must still clear this floor
  ,4     AS min_hist_weeks;      -- fewer than this, range test is not trustworthy

CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_material_points` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
cfg AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_materiality_config`),

cur AS (
  SELECT country, level_1, level_2, nmv, bills, aov, units_per_bill,
         nmv_min_8wk, nmv_max_8wk, nmv_avg_8wk, bills_min_8wk, bills_max_8wk,
         aov_min_8wk, aov_max_8wk, hist_weeks_available
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
  WHERE is_current_week AND level_3 IS NULL
),
-- level_3 is rolled up to level_2 for the point list; attribution detail already
-- lives in dash_action_context and is joined in later.
cur2 AS (
  SELECT t.country, t.level_1, t.level_2,
         SUM(t.nmv) AS nmv, SUM(t.bills) AS bills,
         SAFE_DIVIDE(SUM(t.nmv), NULLIF(SUM(t.bills),0))   AS aov,
         SAFE_DIVIDE(SUM(t.units), NULLIF(SUM(t.bills),0)) AS units_per_bill,
         MIN(t.nmv_min_8wk) AS nmv_min_8wk, MAX(t.nmv_max_8wk) AS nmv_max_8wk,
         AVG(t.nmv_avg_8wk) AS nmv_avg_8wk,
         MIN(t.aov_min_8wk) AS aov_min_8wk, MAX(t.aov_max_8wk) AS aov_max_8wk,
         MIN(t.bills_min_8wk) AS bills_min_8wk, MAX(t.bills_max_8wk) AS bills_max_8wk,
         MAX(t.hist_weeks_available) AS hist_weeks_available
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly` t
  WHERE t.is_current_week
  GROUP BY 1,2,3
),
prv AS (
  SELECT country, level_2,
         SUM(nmv) AS nmv_p, SUM(bills) AS bills_p,
         SAFE_DIVIDE(SUM(nmv), NULLIF(SUM(bills),0)) AS aov_p
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly` t
  CROSS JOIN p
  WHERE t.week_start = p.prv_wk_start
  GROUP BY 1,2
),
mth AS (
  SELECT country, level_2, attainment_vs_full_month, expected_pace, pace_gap_pp,
         nmv AS mtd_nmv, month_target, is_low_target, is_target_invalid, is_unmapped_channel
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
  WHERE is_current_month
),
calc AS (
  SELECT
     c.country, c.level_1, c.level_2
    ,c.nmv, v.nmv_p, c.nmv - IFNULL(v.nmv_p,0) AS delta_nmv
    ,SAFE_DIVIDE(c.nmv,   NULLIF(v.nmv_p,0))   - 1 AS pct_nmv
    ,SAFE_DIVIDE(c.bills, NULLIF(v.bills_p,0)) - 1 AS pct_bills
    ,SAFE_DIVIDE(c.aov,   NULLIF(v.aov_p,0))   - 1 AS pct_aov
    ,c.bills, v.bills_p, c.aov, v.aov_p, c.units_per_bill
    ,c.nmv_min_8wk, c.nmv_max_8wk, c.nmv_avg_8wk, c.aov_min_8wk, c.aov_max_8wk
    ,c.bills_min_8wk, c.bills_max_8wk, c.hist_weeks_available
    ,m.attainment_vs_full_month, m.expected_pace, m.pace_gap_pp
    ,m.mtd_nmv, m.month_target, m.is_low_target, m.is_target_invalid, m.is_unmapped_channel
  FROM cur2 c
  LEFT JOIN prv v ON v.country = c.country AND v.level_2 = c.level_2
  LEFT JOIN mth m ON m.country = c.country AND m.level_2 = c.level_2
),
flagged AS (
  SELECT calc.*, cfg.*,
    -- R1
    (ABS(IFNULL(pct_nmv,0))   >= cfg.pct_threshold
     OR ABS(IFNULL(pct_bills,0)) >= cfg.pct_threshold
     OR ABS(IFNULL(pct_aov,0))   >= cfg.pct_threshold)                       AS r1_pct
    -- R2 (only where enough history exists to make a range meaningful)
    ,(hist_weeks_available >= cfg.min_hist_weeks
      AND (nmv > nmv_max_8wk OR nmv < nmv_min_8wk
        OR aov > aov_max_8wk OR aov < aov_min_8wk
        OR bills > bills_max_8wk OR bills < bills_min_8wk))                   AS r2_range
    -- R3
    ,(ABS(IFNULL(pace_gap_pp,0)) >= cfg.pace_threshold_pp
      AND NOT IFNULL(is_low_target,FALSE)
      AND NOT IFNULL(is_target_invalid,FALSE))                                AS r3_pace
    ,ROW_NUMBER() OVER (ORDER BY ABS(calc.delta_nmv) DESC)                    AS abs_rank
  FROM calc CROSS JOIN cfg
)
SELECT
   FORMAT('P%02d', ROW_NUMBER() OVER (ORDER BY ABS(delta_nmv) DESC)) AS point_id
  ,country, level_1, level_2
  ,nmv, nmv_p, delta_nmv, pct_nmv
  ,bills, bills_p, pct_bills
  ,aov, aov_p, pct_aov, units_per_bill
  ,nmv_min_8wk, nmv_max_8wk, nmv_avg_8wk, hist_weeks_available
  ,mtd_nmv, month_target, attainment_vs_full_month, expected_pace, pace_gap_pp
  ,r1_pct, r2_range, r3_pace
  ,(p_enable_abs_rule AND abs_rank <= abs_rule_top_n
      AND ABS(delta_nmv) >= abs_rule_min_vnd)                                 AS r4_absolute
  ,IF(delta_nmv >= 0, 'HIGHLIGHT', 'LOWLIGHT')                                AS item_type
  -- human-readable reason, carried into the prompt so the model can explain WHY
  ,ARRAY_TO_STRING(ARRAY(
     SELECT x FROM UNNEST([
        IF(r1_pct,   FORMAT('WoW move >=15%% (NMV %s%%, bills %s%%, AOV %s%%)',
                       FORMAT('%.0f', IFNULL(pct_nmv,0)*100), FORMAT('%.0f', IFNULL(pct_bills,0)*100),
                       FORMAT('%.0f', IFNULL(pct_aov,0)*100)), NULL),
        IF(r2_range, FORMAT('outside trailing 8-week range (%s-%s mVND, now %s)',
                       FORMAT('%.0f', nmv_min_8wk/1e6), FORMAT('%.0f', nmv_max_8wk/1e6),
                       FORMAT('%.0f', nmv/1e6)), NULL),
        IF(r3_pace,  FORMAT('pace off by %spp (%s%% of month target at %s%% elapsed)',
                       FORMAT('%.0f', pace_gap_pp), FORMAT('%.0f', attainment_vs_full_month*100),
                       FORMAT('%.0f', expected_pace*100)), NULL),
        IF(p_enable_abs_rule AND abs_rank <= abs_rule_top_n AND ABS(delta_nmv) >= abs_rule_min_vnd
           AND NOT (r1_pct OR r2_range OR r3_pace),
           FORMAT('largest absolute mover (%s mVND) though below percentage thresholds',
                       FORMAT('%.0f', delta_nmv/1e6)), NULL)
     ]) x WHERE x IS NOT NULL), '; ')                                          AS material_reason
FROM flagged
WHERE r1_pct OR r2_range OR r3_pace
   OR (p_enable_abs_rule AND abs_rank <= abs_rule_top_n AND ABS(delta_nmv) >= abs_rule_min_vnd);


/* -----------------------------------------------------------------------------
   4. v_dash_ai_facts_core  -- REPLACED: trend series + material points
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_ai_facts_core` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

common AS (
  SELECT CONCAT(
'You write board-level retail performance commentary for LSOUL (fashion retail; Vietnam, Thailand, China).\n',
'Return FOUR fields: exec_summary_en, exec_summary_vi, highlights_en, highlights_vi, actions_vi.\n\n',
'HARD RULES (apply to every field, both languages):\n',
'1. Use ONLY the supplied numbers. NEVER compute, re-derive, infer or estimate any number.\n',
'2. Numbers identical across languages - same digits, signs and units. Do not localise separators.\n',
'3. Traffic and footfall data DO NOT EXIST in this dataset. Never state or imply traffic moved.\n',
'4. If a fact is not supplied, say nothing about it. Refuse to speculate.\n',
'5. NEVER copy a number out of these instructions. Any digit in an example or a\n',
'   format template is a placeholder, not data. Every figure you write must come\n',
'   from the SUMMARY, TREND SERIES or MATERIAL POINTS blocks below.\n\n',
'MATERIALITY - this is the core editorial rule:\n',
'5. The MATERIAL POINTS list below has ALREADY been filtered in SQL. Write about those points\n',
'   and NOTHING else. Do not mention a channel that is not in the list, however large it looks\n',
'   in the trend series - if it is not listed, it did not clear the threshold and the board\n',
'   should not see it.\n',
'6. CONSISTENCY: EVERY point in the list must be covered in exec_summary AND in\n',
'   highlights/lowlights. Do not drop a point because it seems minor - it is in the list\n',
'   precisely because it cleared the threshold. If there are more points than sentences you\n',
'   are allowed, group several into one sentence rather than omitting any.\n',
'   Cite each point by its ID (P01, P02...) at the end of the sentence that covers it.\n',
'   A point covered in one field but missing from another is a failure.\n\n',
'EXEC SUMMARY - 3 to 5 sentences, in this exact order:\n',
'   a) last week versus the prior week (WoW)\n',
'   b) current month-to-date performance\n',
'   c) progress against the monthly target INCLUDING pace, phrased like\n',
'      "NN% of target at day D of M - behind pace"  (placeholders, NOT values:\n',
'       substitute the real figures supplied below. A digit appearing in this\n',
'       instruction is never a fact about the business.)\n',
'      For pace you MUST use ATTAINMENT vs FULL-MONTH target, never the pro-rated MTD\n',
'      attainment. They are different numbers: pairing the pro-rated figure with "day N of M"\n',
'      states the opposite of the truth. The pace verdict is supplied - reproduce it, do not\n',
'      re-derive it.\n',
'   Use the trend series to say whether a move continues or breaks an existing direction.\n\n',
'LANGUAGE RULES:\n',
'A. Section headings stay ENGLISH in both versions: "**Highlight -**", "**Lowlight -**", "ACTIONS:".\n',
'B. Channel identifiers, store names and SKU codes stay EXACTLY as written. Never translate them.\n',
'C. Owner tags in [brackets] stay EXACTLY as written. Never translate them.\n',
'D. Vietnamese must be natural, professional retail / e-commerce business Vietnamese with full\n',
'   diacritics - NOT word-for-word translation. Use standard trade vocabulary (doanh thu, hóa đơn,\n',
'   giá trị giỏ hàng, tồn kho, tỷ lệ bán ra, chỉ tiêu, tiến độ, tốc độ bán).\n',
'E. You do NOT rewrite the English actions - they are final and appended from SQL.\n',
'   Return actions_vi only: translate each action line, keeping the [Owner] tag, every number,\n',
'   every SKU code and every store / platform name EXACTLY. Same count, same order.\n\n') AS r
),

-- compact sparkline: 8 prior weeks, mVND, oldest to newest
spark_w AS (
  SELECT country, level_2,
    STRING_AGG(FORMAT('%.0f', nmv/1e6), ',' ORDER BY week_start) AS nmv_series,
    STRING_AGG(FORMAT('%d', bills),     ',' ORDER BY week_start) AS bills_series
  FROM (
    SELECT week_start, country, level_2, SUM(nmv) AS nmv, SUM(bills) AS bills
    FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly` t
    CROSS JOIN p WHERE NOT t.is_current_week
    GROUP BY 1,2,3
  ) GROUP BY country, level_2
),
spark_m AS (
  SELECT country, level_2,
    STRING_AGG(FORMAT('%s:%s%%', FORMAT_DATE('%b', month_start),
        IFNULL(FORMAT('%.0f', attainment_vs_full_month*100),'n/a')), ' ' ORDER BY month_start) AS attain_series
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
  WHERE NOT is_low_target AND NOT is_target_invalid
  GROUP BY country, level_2
),
trend_block AS (
  SELECT STRING_AGG(
    FORMAT('%s / %s | NMV 8wk: %s | bills 8wk: %s | monthly attainment: %s',
      s.country, s.level_2, s.nmv_series, s.bills_series, IFNULL(sm.attain_series,'no target')),
    '\n' ORDER BY s.country, s.level_2) AS block
  FROM spark_w s LEFT JOIN spark_m sm USING (country, level_2)
),
points_block AS (
  SELECT STRING_AGG(
    FORMAT('%s | %s | %s / %s | NMV %s->%s mVND (%s mVND, %s%%) | bills %d->%d (%s%%) | AOV %s->%s kVND (%s%%) | UPT %s | MTD %s of %s mVND, %s%% at %s%% elapsed, pace %spp | 8wk range %s-%s mVND | WHY: %s',
      point_id, item_type, country, level_2,
      FORMAT('%.0f', nmv_p/1e6), FORMAT('%.0f', nmv/1e6),
      FORMAT('%.0f', delta_nmv/1e6), FORMAT('%.0f', IFNULL(pct_nmv,0)*100),
      bills_p, bills, FORMAT('%.0f', IFNULL(pct_bills,0)*100),
      FORMAT('%.0f', aov_p/1e3), FORMAT('%.0f', aov/1e3), FORMAT('%.0f', IFNULL(pct_aov,0)*100),
      FORMAT('%.1f', IFNULL(units_per_bill,0)),
      FORMAT('%.0f', IFNULL(mtd_nmv,0)/1e6), FORMAT('%.0f', IFNULL(month_target,0)/1e6),
      IFNULL(FORMAT('%.0f', attainment_vs_full_month*100),'n/a'),
      FORMAT('%.0f', IFNULL(expected_pace,0)*100),
      IFNULL(FORMAT('%.0f', pace_gap_pp),'n/a'),
      FORMAT('%.0f', nmv_min_8wk/1e6), FORMAT('%.0f', nmv_max_8wk/1e6),
      material_reason),
    '\n' ORDER BY point_id) AS block
  FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
),
acts AS (
  SELECT pg.page,
         STRING_AGG(a.action_item, '\n' ORDER BY a.section, a.action_no) AS action_block
  FROM (SELECT 'PAGE1_WOW' AS page UNION ALL SELECT 'PAGE2_MTD') pg
  JOIN `marine-cycle-484213-b4.reportdb.dash_action_items` a
    ON a.page = pg.page OR a.page = 'BOTH'
  GROUP BY pg.page
),
sm AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_page_summary`),

-- Pace MUST use the full-month denominator. Attainment vs the PRO-RATED MTD target
-- and attainment vs the FULL-MONTH target are different numbers with different
-- meanings, and mixing them produces a false pace claim. Measured live: 84% vs the
-- pro-rated target but 32% vs the full month at 42% elapsed. Pairing "84%" with
-- "day 13 of 31" reads as comfortably ahead when the business is 10pp behind.
-- Both are therefore passed, explicitly labelled, with the pace verdict pre-computed.
tot AS (
  SELECT
     SUM(m.mtd_actual_nmv)                                  AS mtd_actual
    ,SUM(IF(m.is_unmapped_channel, 0, m.full_month_target)) AS full_month_target
    ,SAFE_DIVIDE(SUM(m.mtd_actual_nmv),
       NULLIF(SUM(IF(m.is_unmapped_channel, 0, m.full_month_target)),0)) AS attain_full_month
    ,ANY_VALUE(p.mtd_days_elapsed)                          AS days_elapsed
    ,ANY_VALUE(p.month_total_days)                          AS days_total
    ,SAFE_DIVIDE(ANY_VALUE(p.mtd_days_elapsed), ANY_VALUE(p.month_total_days)) AS elapsed_share
    ,(SAFE_DIVIDE(SUM(m.mtd_actual_nmv),
        NULLIF(SUM(IF(m.is_unmapped_channel, 0, m.full_month_target)),0))
      - SAFE_DIVIDE(ANY_VALUE(p.mtd_days_elapsed), ANY_VALUE(p.month_total_days))) * 100 AS pace_gap_pp
    ,IF(SAFE_DIVIDE(SUM(m.mtd_actual_nmv),
          NULLIF(SUM(IF(m.is_unmapped_channel, 0, m.full_month_target)),0))
        >= SAFE_DIVIDE(ANY_VALUE(p.mtd_days_elapsed), ANY_VALUE(p.month_total_days)),
        'ahead of pace', 'behind pace')                     AS pace_verdict
  FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd` m CROSS JOIN p
),

pages AS (
  SELECT
     s.page
    ,s.period_label
    ,CONCAT(
       CASE s.page
         WHEN 'PAGE1_WOW' THEN CONCAT(
           'PAGE: Week over Week. PERIOD: ', s.period_label, '\n',
           'TOTAL: NMV ', FORMAT('%.0f', s.headline_reference/1e6), ' -> ',
           FORMAT('%.0f', s.headline_actual/1e6), ' mVND (',
           FORMAT('%.0f', s.headline_pct*100), '%), ', CAST(s.bills AS STRING), ' bills.\n')
         ELSE CONCAT(
           'PAGE: Month to Date vs Target. PERIOD: ', s.period_label, '\n',
           'TOTAL MTD actual: ', FORMAT('%.0f', s.headline_actual/1e6), ' mVND\n',
           'ATTAINMENT vs PRO-RATED MTD target (', FORMAT('%.0f', s.headline_reference/1e6),
             ' mVND): ', FORMAT('%.0f', s.headline_pct*100), '%  <- headline attainment\n',
           'ATTAINMENT vs FULL-MONTH target (', FORMAT('%.0f', tot.full_month_target/1e6),
             ' mVND): ', FORMAT('%.0f', tot.attain_full_month*100), '%  <- USE THIS ONE FOR PACE\n',
           'ELAPSED: day ', CAST(tot.days_elapsed AS STRING), ' of ', CAST(tot.days_total AS STRING),
             ' = ', FORMAT('%.0f', tot.elapsed_share*100), '%\n',
           'PACE: ', FORMAT('%.0f', tot.pace_gap_pp), 'pp -> ', tot.pace_verdict, '\n',
           'HEADLINE CAVEAT (state verbatim once at the end): ', s.headline_note, '\n')
       END,
       'DATA NOTE: ', s.data_as_of_note, '\n\n',
       'TREND SERIES (8 prior weeks, oldest first, mVND; and last 6 months attainment):\n',
       tb.block, '\n\n',
       'MATERIAL POINTS (already filtered - write about THESE ONLY):\n',
       IFNULL(pb.block, '(no points cleared the materiality thresholds this period)')
     ) AS facts_block
    ,IFNULL(a.action_block, '') AS action_block
  FROM sm s
  CROSS JOIN trend_block tb
  CROSS JOIN points_block pb
  CROSS JOIN tot
  LEFT JOIN acts a ON a.page = s.page
)
SELECT
   pg.page
  ,pg.period_label
  ,REPLACE(pg.period_label, ' ', '') AS period_key
  ,TO_HEX(MD5(CONCAT(pg.facts_block, '||', pg.action_block))) AS facts_hash
  ,CONCAT(c.r, pg.facts_block,
     '\n\nACTIONS TO TRANSLATE (return in actions_vi, same order):\n', pg.action_block,
     '\n\nexec_summary: 3-5 sentences, order a) WoW b) MTD c) target progress with pace.',
     ' highlights_en / highlights_vi: one sentence per material point, tagged with its point ID.'
   ) AS prompt
  ,pg.facts_block
  ,pg.action_block
FROM pages pg CROSS JOIN common c;


/* -----------------------------------------------------------------------------
   4b. v_dash_ai_facts  -- passthrough wrapper
   -----------------------------------------------------------------------------
   sp_dash_generate_ai reads THIS view, not the _core one. Defined here as a plain
   passthrough so 04 runs standalone; 05_review_and_feedback.sql then REPLACES it
   with a guidance-aware version that prepends reviewer-approved style guidance.
   This is the one intentional re-definition in the set: 04 gives you a working
   pipeline, 05 upgrades it. Run 05 after 04 and the guidance layer takes effect.
   ----------------------------------------------------------------------------- */


CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` AS
SELECT page, period_label, period_key, facts_hash, prompt, facts_block, action_block,
       0 AS guidance_version
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts_core`;


/* -----------------------------------------------------------------------------
   5. dash_ai_narrative -- REPLACED to carry exec_summary
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_narrative` (
   page            STRING NOT NULL
  ,period_key      STRING NOT NULL
  ,period_label    STRING
  ,facts_hash      STRING
  ,exec_summary_en STRING
  ,exec_summary_vi STRING
  ,narrative_en    STRING
  ,narrative_vi    STRING
  ,model_endpoint  STRING
  ,prompt_tokens   INT64
  ,output_tokens   INT64
  ,gen_status      STRING
  ,generated_at    TIMESTAMP
)
OPTIONS(description="Cached bilingual narrative with executive summary. Written only by sp_dash_generate_ai.");


/* -----------------------------------------------------------------------------
   6. sp_dash_generate_ai -- REPLACED for the 5-field schema
   
   Measured on the 2026-09-04 run:

     PAGE1_WOW   prompt 4,516 tok   output 5,000 tok   gen_status EMPTY_EXEC
                 exec_summary_en/vi, narrative_en/vi all returned 0 characters
     PAGE2_MTD   prompt 4,534 tok   output 1,611 tok   gen_status OK

   output_tokens landed exactly on max_output_tokens, so generation was truncated
   mid-structure and every field came back empty - the page then failed review on
   all 8 material points and quarantined. PAGE2_MTD survived only because it had
   8 action lines to translate against PAGE1_WOW's 10.

   5,000 was sized for 5 material points, one language pair, and a shorter action
   block. The prompt now also asks for marketing coverage, so the ceiling moves to
   8,192. Input is not the constraint - both prompts sit near 4,500 tokens.
   ========================================================================== */
CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(i_force BOOL)
OPTIONS(
  description="Generates exec summary + bilingual narrative. Max 2 model calls per run; 0 if nothing changed.")
BEGIN
  DECLARE v_pending INT64;

  CREATE OR REPLACE TEMP TABLE t_pending AS
  SELECT f.page, f.period_key, f.period_label, f.facts_hash, f.prompt, f.action_block
  FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` f
  LEFT JOIN `marine-cycle-484213-b4.reportdb.dash_ai_narrative` c
         ON c.page = f.page AND c.period_key = f.period_key
  WHERE IFNULL(i_force, FALSE)
     OR c.page IS NULL
     OR c.facts_hash IS DISTINCT FROM f.facts_hash
     OR c.gen_status <> 'OK';

  SET v_pending = (SELECT COUNT(*) FROM t_pending);
  IF v_pending = 0 THEN
    SELECT 'Cache hit - 0 model calls made.' AS run_note; RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE t_gen AS
  SELECT page, period_key, period_label, facts_hash,
    AI.GENERATE(
       prompt,
       connection_id => 'marine-cycle-484213-b4.asia-southeast1.agent_platform_ai',
       endpoint      => 'gemini-2.5-flash',
       model_params  => JSON '{"generation_config":{"max_output_tokens":8192,"temperature":0.2}}',
       output_schema => 'exec_summary_en STRING, exec_summary_vi STRING, highlights_en STRING, highlights_vi STRING, actions_vi STRING'
    ) AS g
  FROM t_pending;

  MERGE `marine-cycle-484213-b4.reportdb.dash_ai_narrative` t
  USING (
    SELECT t.page, t.period_key, t.period_label, t.facts_hash
      ,g.exec_summary_en, g.exec_summary_vi
      ,CONCAT(g.highlights_en, '\n\nACTIONS:\n', p.action_block) AS narrative_en
      ,CONCAT(g.highlights_vi, '\n\nACTIONS:\n', g.actions_vi)   AS narrative_vi
      ,'gemini-2.5-flash' AS model_endpoint
      ,CAST(JSON_VALUE(g.full_response,'$.usage_metadata.prompt_token_count')     AS INT64) AS prompt_tokens
      ,CAST(JSON_VALUE(g.full_response,'$.usage_metadata.candidates_token_count') AS INT64) AS output_tokens
      -- TRUNCATED is distinguished from EMPTY_EXEC so a token-ceiling failure is not
      -- mistaken for a model refusal. Both are non-OK, so both still force a regeneration.
      ,CASE WHEN CAST(JSON_VALUE(g.full_response,'$.usage_metadata.candidates_token_count') AS INT64) >= 8192
                 THEN 'TRUNCATED'
            WHEN g.exec_summary_en IS NULL OR g.exec_summary_en = '' THEN 'EMPTY_EXEC'
            WHEN g.highlights_en   IS NULL OR g.highlights_en   = '' THEN 'EMPTY_EN'
            WHEN g.highlights_vi   IS NULL OR g.highlights_vi   = '' THEN 'EMPTY_VI'
            WHEN g.actions_vi      IS NULL OR g.actions_vi      = '' THEN 'EMPTY_ACTIONS_VI'
            ELSE 'OK' END AS gen_status
    FROM t_gen t JOIN t_pending p USING (page, period_key)
  ) s
  ON t.page = s.page AND t.period_key = s.period_key
  WHEN MATCHED THEN UPDATE SET
     facts_hash = s.facts_hash, exec_summary_en = s.exec_summary_en,
     exec_summary_vi = s.exec_summary_vi, narrative_en = s.narrative_en,
     narrative_vi = s.narrative_vi, model_endpoint = s.model_endpoint,
     prompt_tokens = s.prompt_tokens, output_tokens = s.output_tokens,
     gen_status = s.gen_status, generated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT
    (page, period_key, period_label, facts_hash, exec_summary_en, exec_summary_vi,
     narrative_en, narrative_vi, model_endpoint, prompt_tokens, output_tokens,
     gen_status, generated_at)
  VALUES
    (s.page, s.period_key, s.period_label, s.facts_hash, s.exec_summary_en, s.exec_summary_vi,
     s.narrative_en, s.narrative_vi, s.model_endpoint, s.prompt_tokens, s.output_tokens,
     s.gen_status, CURRENT_TIMESTAMP());

  SELECT FORMAT('Generated %d page narrative(s) with exec summary, EN + VI.', v_pending) AS run_note;
END;


/* -----------------------------------------------------------------------------
   7. v_dash_report -- REPLACED to expose exec_summary
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_report` AS
WITH rule_text AS (
  SELECT page,
    STRING_AGG(FORMAT('**%s -** %s / %s NMV %s %s%% (%s mVND) [%s]',
        IF(item_type='HIGHLIGHT','Highlight','Lowlight'), country, level_2,
        IF(delta_nmv >= 0,'rose','fell'), FORMAT('%.0f', ABS(IFNULL(pct_nmv,0))*100),
        FORMAT('%.0f', delta_nmv/1e6), point_id),
      '\n' ORDER BY point_id) AS rule_narrative_en,
    STRING_AGG(FORMAT('**%s -** %s / %s NMV %s %s%% (%s mVND) [%s]',
        IF(item_type='HIGHLIGHT','Highlight','Lowlight'),
        CASE country WHEN 'VIETNAM' THEN 'Việt Nam' WHEN 'THAILAND' THEN 'Thái Lan'
                     WHEN 'CHINA' THEN 'Trung Quốc' ELSE country END,
        level_2, IF(delta_nmv >= 0,'tăng','giảm'),
        FORMAT('%.0f', ABS(IFNULL(pct_nmv,0))*100), FORMAT('%.0f', delta_nmv/1e6), point_id),
      '\n' ORDER BY point_id) AS rule_narrative_vi
  FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
  CROSS JOIN (SELECT 'PAGE1_WOW' AS page UNION ALL SELECT 'PAGE2_MTD')
  GROUP BY page
),
rule_actions AS (
  SELECT pg.page, STRING_AGG(a.action_item, '\n' ORDER BY a.section, a.action_no) AS action_block
  FROM (SELECT 'PAGE1_WOW' AS page UNION ALL SELECT 'PAGE2_MTD') pg
  JOIN `marine-cycle-484213-b4.reportdb.dash_action_items` a
    ON a.page = pg.page OR a.page = 'BOTH'
  GROUP BY pg.page
)
SELECT
   s.page, s.period_label
  ,s.headline_actual, s.headline_reference, s.headline_pct
  ,s.excluded_target, s.pct_including_excluded, s.bills, s.basket
  ,s.data_as_of_note, s.headline_note
  ,n.exec_summary_en
  ,n.exec_summary_vi
  ,COALESCE(n.narrative_en, CONCAT(r.rule_narrative_en, '\n\nACTIONS:\n', IFNULL(ra.action_block,''))) AS narrative_en
  ,COALESCE(n.narrative_vi, CONCAT(r.rule_narrative_vi, '\n\nACTIONS:\n', IFNULL(ra.action_block,''))) AS narrative_vi
  ,r.rule_narrative_en, r.rule_narrative_vi
  ,ra.action_block AS action_block_en
  ,CASE WHEN n.narrative_en IS NULL THEN 'RULE'
        WHEN n.facts_hash IS DISTINCT FROM f.facts_hash THEN 'AI_STALE'
        WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), n.generated_at, DAY) > 7 THEN 'AI_STALE'
        ELSE 'AI' END AS narrative_source
  ,n.generated_at AS ai_generated_at, n.model_endpoint
FROM `marine-cycle-484213-b4.reportdb.dash_page_summary` s
LEFT JOIN rule_text    r  ON r.page  = s.page
LEFT JOIN rule_actions ra ON ra.page = s.page
LEFT JOIN `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` f ON f.page = s.page
LEFT JOIN `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
       ON n.page = s.page AND n.period_key = f.period_key;


/* -----------------------------------------------------------------------------
   8. v_dash_consistency_check -- enforces requirement 4 deterministically
   -----------------------------------------------------------------------------
   Every material point must appear in exec_summary AND in the highlights.
   Any point ID cited that is not in the point list is a fabricated reference.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_consistency_check` AS
WITH pts AS (
  SELECT point_id, ABS(delta_nmv) AS abs_impact
  FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
),
top3 AS (SELECT point_id FROM pts ORDER BY abs_impact DESC LIMIT 3),
n AS (
  SELECT page, period_key, exec_summary_en, narrative_en FROM (
    SELECT page, period_key, exec_summary_en, narrative_en,
           ROW_NUMBER() OVER (PARTITION BY page ORDER BY generated_at DESC) rn
    FROM `marine-cycle-484213-b4.reportdb.dash_ai_narrative`
  ) WHERE rn = 1
),
cover AS (
  SELECT n.page, n.period_key, p.point_id,
         REGEXP_CONTAINS(IFNULL(n.narrative_en,''),    p.point_id) AS in_narrative,
         REGEXP_CONTAINS(IFNULL(n.exec_summary_en,''), p.point_id) AS in_exec,
         p.point_id IN (SELECT point_id FROM top3)                 AS is_top3
  FROM n CROSS JOIN pts p
),
fab AS (
  SELECT n.page, ARRAY_AGG(DISTINCT x) AS fabricated_point_ids
  FROM n, UNNEST(REGEXP_EXTRACT_ALL(
         CONCAT(IFNULL(n.exec_summary_en,''),' ',IFNULL(n.narrative_en,'')), r'\b[PM][0-9]{2}\b')) x
  WHERE x NOT IN (SELECT point_id FROM pts)
  GROUP BY n.page
),
agg AS (
  SELECT page,
         ANY_VALUE(period_key) AS period_key,
         COUNT(*) AS material_points,
         IFNULL(ARRAY_AGG(IF(NOT in_narrative, point_id, NULL) IGNORE NULLS),
                ARRAY<STRING>[]) AS missing_from_highlights,
         IFNULL(ARRAY_AGG(IF(is_top3 AND NOT in_exec, point_id, NULL) IGNORE NULLS),
                ARRAY<STRING>[]) AS missing_from_exec_summary_top3
  FROM cover GROUP BY page
)
SELECT
   a.page
  ,a.period_key
  ,a.material_points
  ,a.missing_from_highlights
  ,a.missing_from_exec_summary_top3
  ,IFNULL(f.fabricated_point_ids, ARRAY<STRING>[]) AS fabricated_point_ids
  ,ARRAY_LENGTH(a.missing_from_highlights) = 0
   AND ARRAY_LENGTH(IFNULL(f.fabricated_point_ids, ARRAY<STRING>[])) = 0 AS consistency_pass
FROM agg a
LEFT JOIN fab f USING (page);


/* -----------------------------------------------------------------------------
   9. v_dash_ai_cost
   -----------------------------------------------------------------------------
   Cost computed from the token counts the procedure actually stored, not from an
   assumption. Rates declared in ONE place - update here if pricing or model changes.

   RATES (Vertex AI, gemini-2.5-flash, verified 2026-08-11):
       input  $0.30 per 1M tokens
       output $2.50 per 1M tokens
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_ai_cost` AS
WITH rates AS (SELECT 0.30 AS usd_per_1m_input, 2.50 AS usd_per_1m_output)
SELECT
   n.page, n.period_label, n.model_endpoint, n.gen_status
  ,n.prompt_tokens, n.output_tokens
  ,ROUND(n.prompt_tokens/1e6 * r.usd_per_1m_input
       + n.output_tokens/1e6 * r.usd_per_1m_output, 6) AS usd_this_generation
  ,n.generated_at
FROM `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
CROSS JOIN rates r;


/* =============================================================================
   VALIDATION
   ============================================================================= */

-- V1. Weekly series. EXPECT 8 prior weeks + current, no NaN.
SELECT week_start, country, level_2, ROUND(nmv/1e6) AS nmv_m, bills,
       ROUND(aov/1e3) AS aov_k, ROUND(units_per_bill,1) AS upt,
       bills_incl_zero - bills AS phantom_bills,
       is_current_week, hist_weeks_available
FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
WHERE level_3 IS NULL OR level_3 IS NOT NULL
ORDER BY country, level_2, week_start;

-- V2. NaN guard worked. EXPECT zero rows.
SELECT week_start, country, level_2 FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
WHERE IS_NAN(nmv) OR IS_NAN(aov);

-- V3. Monthly series + pace. EXPECT 6 months per channel.
SELECT month_start, country, level_2, ROUND(nmv/1e6) AS nmv_m,
       ROUND(month_target/1e6) AS target_m,
       ROUND(attainment_vs_full_month*100) AS attain_pct,
       ROUND(expected_pace*100) AS expected_pct,
       ROUND(pace_gap_pp) AS pace_gap_pp, is_current_month
FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
WHERE NOT is_low_target AND NOT is_unmapped_channel
ORDER BY country, level_2, month_start;

-- V4. THE KEY CHECK: which points cleared, and on which rule?
--     EXPECT VN Offline Store present only via r4_absolute.
SELECT point_id, item_type, country, level_2,
       ROUND(delta_nmv/1e6) AS delta_m, ROUND(pct_nmv*100) AS nmv_pct,
       ROUND(pct_bills*100) AS bills_pct, ROUND(pct_aov*100) AS aov_pct,
       ROUND(pace_gap_pp) AS pace_pp,
       r1_pct, r2_range, r3_pace, r4_absolute, material_reason
FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
ORDER BY point_id;

-- V5. What R4 rescues. EXPECT VN Offline Store, -216 mVND.
SELECT point_id, country, level_2, ROUND(delta_nmv/1e6) AS delta_m, material_reason
FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
WHERE r4_absolute AND NOT (r1_pct OR r2_range OR r3_pace);

-- V6. Generate, then read the exec summary.
CALL `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(TRUE);
SELECT page, exec_summary_en FROM `marine-cycle-484213-b4.reportdb.v_dash_report` ORDER BY page;
SELECT page, exec_summary_vi FROM `marine-cycle-484213-b4.reportdb.v_dash_report` ORDER BY page;

-- V7. Consistency. EXPECT consistency_pass = true and no fabricated IDs.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_consistency_check`;

-- V8. Prompt size check before paying for it.
SELECT page, LENGTH(prompt) AS prompt_chars, ROUND(LENGTH(prompt)/4) AS approx_tokens
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` ORDER BY page;