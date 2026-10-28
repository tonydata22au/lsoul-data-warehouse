CREATE VIEW `marine-cycle-484213-b4.reportdb.v_mtd_prompt`
AS WITH
p AS (
SELECT
   CURRENT_DATE('Asia/Ho_Chi_Minh') AS today_vn
  ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY)   AS report_date
  ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 7 DAY)   AS same_period_prv_week_report_date
  ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 MONTH) AS same_period_prv_month_report_date
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
  FROM (
    SELECT
     CURRENT_DATE('Asia/Ho_Chi_Minh')                                   AS today_vn
    ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 DAY)         AS report_date
    ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 7 DAY)         AS same_period_prv_week_report_date
    ,DATE_SUB(CURRENT_DATE('Asia/Ho_Chi_Minh'), INTERVAL 1 MONTH)       AS same_period_prv_month_report_date
  ) b
  ),

mtd_window AS (
  SELECT
     p.report_date
    ,p.month_start
    ,p.mtd_days_elapsed
    ,p.month_total_days
    ,p.month_total_days - p.mtd_days_elapsed  AS days_left
    ,DATE_SUB(p.month_start, INTERVAL 1 MONTH) AS prv_month_start
    ,LAST_DAY(DATE_SUB(p.month_start, INTERVAL 1 MONTH)) AS prv_month_end
  FROM p
),

mtd_rows AS (
  SELECT b.*
  FROM `marine-cycle-484213-b4.reportdb.performance_snapshot_v2_base` b, mtd_window m 
  WHERE b.month_start = m.month_start
    AND b.period_date <= m.report_date          -- NEW: never read future rows
),

mtd_overall AS (
  SELECT
    ANY_VALUE(monthly_revenue)          AS mtd_revenue,
    ANY_VALUE(prev_monthly_revenue)     AS prior_month_revenue,
    ANY_VALUE(target_revenue_monthly)   AS full_month_target,
    ANY_VALUE(pct_achievement_monthly)  AS pct_achievement,
    ANY_VALUE(mom_growth_pct)           AS mom_growth
  FROM mtd_rows
),

/* NEW: pace, computed here so the model never has to. */
mtd_pace AS (
  SELECT
     o.*
    ,m.days_left
    ,IFNULL(o.full_month_target,0) - IFNULL(o.mtd_revenue,0)            AS gap_to_target
    ,SAFE_DIVIDE(o.mtd_revenue, NULLIF(m.mtd_days_elapsed,0))           AS achieved_daily
    ,SAFE_DIVIDE(IFNULL(o.full_month_target,0) - IFNULL(o.mtd_revenue,0),
                 NULLIF(m.days_left,0))                                 AS required_daily
  FROM mtd_overall o, mtd_window m
),

mtd_country_level3 AS (
  SELECT DISTINCT country, level_3,
    monthly_revenue_by_country_level_3        AS revenue,
    prev_monthly_revenue_country_level_3      AS prior_revenue
  FROM mtd_rows
),

mtd_by_country AS (
  SELECT country,
    SUM(IFNULL(revenue, 0))       AS revenue,
    SUM(IFNULL(prior_revenue, 0)) AS prior_revenue
  FROM mtd_country_level3
  GROUP BY 1
),

/* Each line carries the absolute change so the model never subtracts. The
   header on these blocks names the basis; HARD RULE 4 governs how it is read. */
mtd_country_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ': month-to-date ', FORMAT("%'d", CAST(ROUND(revenue) AS INT64)),
      ', full prior month ', FORMAT("%'d", CAST(ROUND(prior_revenue) AS INT64)),
      ', change ', FORMAT("%'d", CAST(ROUND(revenue - prior_revenue) AS INT64)),
      ' (', IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%)'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM mtd_by_country
),

mtd_channel_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ' / ', IFNULL(level_3, 'n/a'),
      ': month-to-date ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', full prior month ', FORMAT("%'d", CAST(ROUND(IFNULL(prior_revenue, 0)) AS INT64)),
      ', change ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue,0) - IFNULL(prior_revenue,0)) AS INT64)),
      ' (', IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%)'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM mtd_country_level3
)

SELECT
  'MTD' AS report_type,

  /* matches dash_page_summary PAGE2_MTD: "2026-09-01 to 2026-09-06 (day 6 of 30)" */
  CONCAT(CAST(m.month_start AS STRING), ' to ', CAST(m.report_date AS STRING),
         ' (day ', CAST(m.mtd_days_elapsed AS STRING),
         ' of ', CAST(m.month_total_days AS STRING), ')')
    AS period_label,

  CONCAT(
'You write board-level retail performance commentary for LSOUL (fashion retail; Vietnam, Thailand, China).\n',
'This is the Month-to-Date review. All figures are VND.\n\n',

'REPORTING WINDOW\n',
'  Month to date: ', CAST(m.month_start AS STRING), ' to ', CAST(m.report_date AS STRING),
                     ' (day ', CAST(m.mtd_days_elapsed AS STRING), ' of ', CAST(m.month_total_days AS STRING), ')\n',
'  Comparison:    ', CAST(m.prv_month_start AS STRING), ' to ', CAST(m.prv_month_end AS STRING),
                     ' - the FULL prior month\n\n',

'HARD RULES\n',
'1. Use ONLY the numbers supplied below. NEVER compute, re-derive, infer or estimate a number.\n',
'   Every figure you need - including the gap to target and the per-day rates - is already given.\n',
'2. If a fact is not supplied, say nothing about it. Refuse to speculate. Do not mention\n',
'   traffic, sessions, footfall, advertising spend or stock: none of it is supplied here.\n',
'3. Country names, and level_3 platform and store names stay EXACTLY as written. Never translate\n',
'   or transliterate them (Shopee, TikTok, Xiaohongshu, Store Nguyễn Trãi).\n',
  IF(m.days_left <= 0,
    CONCAT(
'4. PERIOD COMPLETENESS. The month is COMPLETE: ', CAST(m.mtd_days_elapsed AS STRING),
     ' of ', CAST(m.month_total_days AS STRING), ' days.\n',
'   The comparison against the prior month is like-for-like and may be described as growth\n',
'   or decline.\n'),
    CONCAT(
'4. PERIOD COMPLETENESS - THIS IS A PARTIAL MONTH, AND THE COMPARISON IS NOT LIKE-FOR-LIKE.\n',
'   Month-to-date covers ', CAST(m.mtd_days_elapsed AS STRING), ' of ',
     CAST(m.month_total_days AS STRING), ' days. Every "full prior month" figure below is a\n',
'   COMPLETE ', CAST(m.month_total_days AS STRING), '-day-scale month. So every "change" number\n',
'   compares ', CAST(m.mtd_days_elapsed AS STRING), ' traded days against a whole month.\n',
'   You must NOT describe any of it as a decline, a drop, a fall or underperformance. Most of\n',
'   the difference is days that have not been traded yet, not a trading result.\n',
'   Whenever you quote one of these figures, attach the words\n',
'   "', CAST(m.mtd_days_elapsed AS STRING), ' of ', CAST(m.month_total_days AS STRING),
     ' days vs the full prior month".\n',
'   Judge performance on the target and pace figures instead - those are on a like-for-like basis.\n')),
'5. Achievement is month-to-date revenue over the FULL-MONTH target, not a pro-rated one.\n',
'   State it as a share of the full-month target at day ', CAST(m.mtd_days_elapsed AS STRING),
   ' of ', CAST(m.month_total_days AS STRING), '.\n',
'   Pairing that percentage with the day count without saying "of the full-month target" states\n',
'   the opposite of the truth.\n\n',

'OVERALL\n',
'- Revenue month-to-date: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.mtd_revenue, 0)) AS INT64)), '\n',
'- Revenue, full prior month: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.prior_month_revenue, 0)) AS INT64)), '\n',
'- Change vs full prior month (NOT like-for-like, see rule 4): ',
   IFNULL(CAST(ROUND(o.mom_growth * 100, 1) AS STRING), 'n/a'), '%\n',
'- Full-month target: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.full_month_target, 0)) AS INT64)), '\n',
'- Achievement vs full-month target: ', IFNULL(CAST(ROUND(o.pct_achievement * 100, 1) AS STRING), 'n/a'), '%\n',
  /* Sign decides the wording: a negative gap is a target beaten, not a
     shortfall, and required/day is meaningless once the target is met. */
  IF(o.gap_to_target > 0,
     CONCAT('- Still needed to reach the full-month target: ', FORMAT("%'d", CAST(ROUND(o.gap_to_target) AS INT64)), '\n'),
     CONCAT('- Full-month target already exceeded by: ', FORMAT("%'d", CAST(ROUND(-o.gap_to_target) AS INT64)), '\n')),
'- Days left in the month: ', CAST(o.days_left AS STRING), '\n',
'- Revenue per day achieved so far: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.achieved_daily,0)) AS INT64)), '\n',
'- Revenue per day required over the days left: ',
   CASE WHEN o.days_left <= 0       THEN 'n/a (month complete)'
        WHEN o.gap_to_target <= 0   THEN '0 (target already met)'
        ELSE FORMAT("%'d", CAST(ROUND(o.required_daily) AS INT64)) END, '\n',
'- Pace read: achieved per day vs required per day, both above, is the ONLY like-for-like\n',
'  performance comparison available on this page. Use it, not the change-vs-prior-month figure.\n\n',

'BY COUNTRY\n', IFNULL(cl.text, 'No data'), '\n\n',
'BY CHANNEL (country / level_3)\n', IFNULL(chl.text, 'No data'), '\n\n',

'OUTPUT - return EXACTLY these three sections, in this order, and nothing else:\n',
'  SUMMARY   - one sentence on overall month-to-date performance. If the month is not complete,\n',
'              also state how much revenue is still needed to reach the full-month target and\n',
'              the per-day rate that implies over the days left. Both figures are supplied above.\n',
'  HIGHLIGHT - one sentence naming the strongest country and level_3 platform, with its figures.\n',
'  LOWLIGHT  - one sentence naming the weakest country and level_3 platform needing attention,\n',
'              with its figures.\n',
'Do NOT add any other section, category, heading, recommendation list or commentary.\n\n',

'LANGUAGE\n',
'Write all three sections in natural, professional Vietnamese with full diacritics - not a\n',
'word-for-word translation. Use standard retail trade vocabulary (doanh thu, chỉ tiêu, tiến độ,\n',
'lũy kế từ đầu tháng, kênh bán, tăng trưởng). Numbers, country names and platform names stay\n',
'exactly as written above; do not localise digit separators.\n'
  ) AS prompt_text
FROM mtd_pace o, mtd_country_lines cl, mtd_channel_lines chl, mtd_window m;
