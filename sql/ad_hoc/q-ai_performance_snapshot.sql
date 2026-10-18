/* =============================================================================
   v_mtd_prompt   -- ppl-report   -- REWRITTEN 2026-09-07
   -----------------------------------------------------------------------------
   NOTE ON THE NAME: the brief called this v_mth_prompt. The deployed object is
   v_mtd_prompt. Name unchanged, per the naming-convention constraint.

   OUTPUT CONTRACT - UNCHANGED
     report_type STRING, period_label STRING, prompt_text STRING     one row

   WHAT WAS WRONG
   ---------------------------------------------------------------------------
   1. Three different dates, none of them the report date.
        month filter   DATE_TRUNC(CURRENT_DATE(), MONTH)
        period_label   FORMAT_DATE('%B %Y', CURRENT_DATE())
        "data through" DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
      CURRENT_DATE() is UTC, not Vietnam time, and on the 1st of a month the
      label and the reporting period name DIFFERENT MONTHS. "Data through
      yesterday" was a guess about the pipeline, never a fact from it.

   2. The MoM figure is a partial month against a full one. On this run:
        September month-to-date  7.04bn   (6 days)
        August, complete        23.87bn   (31 days)
        mom_growth_pct         -71.0%
      -71% is arithmetic, not trading. The old prompt printed it as
      "MoM change vs prior month" with nothing attached, so the model had no way
      to know it was reading a calendar artefact. Same for every country and
      level_3 line.

      This CANNOT be fixed by capping the prior period, and that is worth being
      explicit about: performance_snapshot_v2_base carries no daily revenue
      column and no as-of history - every August row holds the FINAL full-August
      value - so a same-period-prior-month figure is not derivable from this
      source. Sourcing one would mean joining the ppl-AI tables, which the
      "keep the number of tables/views as it is" constraint rules out. The fix
      here is therefore the same one v_dash_ai_facts_core uses for incomplete
      data: supply the figure, label its basis precisely, and forbid the model
      from reading it as a decline. HARD RULE 4 below does that.

   3. The prompt asked "how much revenue need to go for the current month in
      order to reach the weekly target" while also saying "do not invent
      numbers". The gap was not supplied, so the model had to break one rule to
      obey the other. It is now computed in SQL.

   WHAT CHANGED
     1. CURRENT_DATE() is gone. Everything anchors on dash_run_params.report_date.
     2. mtd_days_elapsed / month_total_days come from dash_run_params, the same
        values dash_page2_mtd reports as "day 6 of 30".
     3. period_date <= report_date guard. The source runs to 2026-09-30 with
        zero-revenue target rows.
     4. period_label matches dash_page_summary PAGE2_MTD:
        "2026-09-01 to 2026-09-06 (day 6 of 30)".
     5. Gap to target, days left, achieved/day and required/day computed in SQL.
     6. Prompt restructured on v_dash_ai_facts_core, keeping this view's own
        MTD content, Vietnamese output and one summary + one highlight + one
        lowlight.

   TABLE-SPECIFIC, DELIBERATELY NOT SHARED WITH v_wow_prompt
     Elapsed-day capping. The month cycle is 28-31 days and the elapsed count
     comes from dash_run_params.mtd_days_elapsed; the week cycle is a fixed 7 and
     v_wow_prompt derives its own from cur_wk_start. The two must not be
     unified: a shared "days elapsed" would silently apply a 7-day denominator
     to a 30-day month. HARD RULE 4 is worded per view for the same reason.
   ========================================================================== */
CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_mtd_prompt` AS
WITH
p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

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
FROM mtd_pace o, mtd_country_lines cl, mtd_channel_lines chl, mtd_window m
/* =============================================================================
   v_wow_prompt   -- ppl-report   -- REWRITTEN 2026-09-07
   -----------------------------------------------------------------------------
   OUTPUT CONTRACT - UNCHANGED
     report_type STRING, period_label STRING, prompt_text STRING     one row
   v_ai_report_prompts does SELECT * ... UNION ALL SELECT * over this and
   v_mtd_prompt, so column order and types must stay exactly as above.

   WHAT WAS WRONG - and this one was live, not theoretical
   ---------------------------------------------------------------------------
   The week was picked as:

       DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL -1 DAY),
                           WEEK(MONDAY)), INTERVAL 0 DAY)

   INTERVAL -1 DAY subtracted ADDS a day, and INTERVAL 0 DAY does nothing, so
   this reduces to "the Monday of the week containing TOMORROW". Run on
   2026-09-07 (a Monday) it resolves to week_start 2026-09-07 - a week that has
   not been traded yet. That row in performance_snapshot_v2_base carries:

       weekly_revenue 0   prev_weekly_revenue 7.94bn
       wow_growth_pct -100%   pct_achievement_weekly 0%

   So the prompt was handing the model an empty week and a -100% collapse and
   asking it to explain the business. The view then tried to patch this in prose:

       "(If today is Monday and the start date of the week starting X is the
        same date as today date, then the week starting is last week)"

   That is arithmetic pushed onto the model. It is removed. The window now comes
   from dash_run_params, the same anchor dash_page1_wow uses.

   WHAT CHANGED
     1. CURRENT_DATE() is gone. Every date derives from dash_run_params.report_date.
     2. Window is cur_wk_start..report_date vs prv_wk_start..prv_wk_end, matching
        dash_page1_wow.
     3. period_date <= report_date guard. The source runs to 2026-09-30 with
        zero-revenue target rows; without the guard those can be picked up.
     4. period_label matches dash_page_summary: both windows stated in full.
     5. Gap-to-target, days remaining, achieved/day and required/day are now
        COMPUTED IN SQL. The old prompt asked the model for "how much revenue
        need to go ... to reach the weekly target" while also telling it not to
        invent numbers - it had to do arithmetic to comply with one rule and
        break the other.
     6. Prompt restructured on v_dash_ai_facts_core (role line, numbered HARD
        RULES, explicit OUTPUT spec, LANGUAGE RULES), keeping this view's own
        content: WoW framing, the same three data blocks, Vietnamese output,
        one summary + one highlight + one lowlight.

   TABLE-SPECIFIC, DELIBERATELY NOT SHARED WITH v_mtd_prompt
     Week completeness is a 7-day question and is decided here. When report_date
     is the Sunday the week is complete and WoW is like-for-like; on any other
     weekday the current week is partial while prev_weekly_revenue is a full
     seven days, and HARD RULE 4 flips to say so. v_mtd_prompt has the same
     shape of problem on a 28-31 day cycle and states its own version.
   ========================================================================== */
CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_wow_prompt` AS
WITH
p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

/* The reporting window. cur_wk_end is not used directly: the full week end is
   rebuilt from cur_wk_start so this stays correct whether dash_run_params caps
   cur_wk_end at report_date or carries the calendar Sunday. */
wow_week AS (
  SELECT
     p.report_date
    ,p.cur_wk_start                                            AS wow_week_start
    ,LEAST(p.report_date, DATE_ADD(p.cur_wk_start, INTERVAL 6 DAY)) AS wow_through
    ,p.prv_wk_start
    ,p.prv_wk_end
    ,DATE_DIFF(LEAST(p.report_date, DATE_ADD(p.cur_wk_start, INTERVAL 6 DAY)),
               p.cur_wk_start, DAY) + 1                        AS wtd_days_elapsed
    ,7                                                         AS week_total_days
  FROM p
),

wow_rows AS (
  SELECT b.*
  FROM `marine-cycle-484213-b4.reportdb.performance_snapshot_v2_base` b, wow_week w
  WHERE b.week_start = w.wow_week_start
    AND b.period_date <= w.report_date          -- NEW: never read future rows
),

wow_overall AS (
  SELECT
    ANY_VALUE(weekly_revenue)          AS wow_revenue,
    ANY_VALUE(prev_weekly_revenue)     AS prior_week_revenue,
    ANY_VALUE(target_revenue_weekly)   AS wow_target,
    ANY_VALUE(pct_achievement_weekly)  AS pct_achievement,
    ANY_VALUE(wow_growth_pct)          AS wow_growth,
    ANY_VALUE(aov_weekly)              AS aov
  FROM wow_rows
),

/* NEW: pace, computed here so the model never has to. */
wow_pace AS (
  SELECT
     o.*
    ,w.week_total_days - w.wtd_days_elapsed                            AS days_left
    ,IFNULL(o.wow_target,0) - IFNULL(o.wow_revenue,0)                  AS gap_to_target
    ,SAFE_DIVIDE(o.wow_revenue, NULLIF(w.wtd_days_elapsed,0))          AS achieved_daily
    ,SAFE_DIVIDE(IFNULL(o.wow_target,0) - IFNULL(o.wow_revenue,0),
                 NULLIF(w.week_total_days - w.wtd_days_elapsed,0))     AS required_daily
  FROM wow_overall o, wow_week w
),

wow_country_level3 AS (
  SELECT DISTINCT country, level_3,
    weekly_revenue_by_country_level_3          AS revenue,
    prev_weekly_revenue_country_level_3        AS prior_revenue,
    aov_weekly_country_level_3                 AS aov
  FROM wow_rows
),

wow_by_country AS (
  SELECT country,
    SUM(IFNULL(revenue, 0))       AS revenue,
    SUM(IFNULL(prior_revenue, 0)) AS prior_revenue
  FROM wow_country_level3
  GROUP BY 1
),

wow_by_level1 AS (
  SELECT DISTINCT level_1,
    weekly_revenue_by_level_1      AS revenue,
    prev_weekly_revenue_level_1    AS prior_revenue
  FROM wow_rows
),

/* Each line now also carries the ABSOLUTE change. Without it the model has to
   subtract to say "fell by X", which HARD RULE 1 forbids. */
wow_country_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ': revenue ', FORMAT("%'d", CAST(ROUND(revenue) AS INT64)),
      ', prior week ', FORMAT("%'d", CAST(ROUND(prior_revenue) AS INT64)),
      ', change ', FORMAT("%'d", CAST(ROUND(revenue - prior_revenue) AS INT64)),
      ' (', IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%)'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_by_country
),

wow_level1_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', level_1, ': revenue ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', prior week ', FORMAT("%'d", CAST(ROUND(IFNULL(prior_revenue, 0)) AS INT64)),
      ', change ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue,0) - IFNULL(prior_revenue,0)) AS INT64)),
      ' (', IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%)'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_by_level1
),

wow_channel_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ' / ', IFNULL(level_3, 'n/a'),
      ': revenue ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', prior week ', FORMAT("%'d", CAST(ROUND(IFNULL(prior_revenue, 0)) AS INT64)),
      ', change ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue,0) - IFNULL(prior_revenue,0)) AS INT64)),
      ' (', IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%)',
      ', AOV ', FORMAT("%'d", CAST(ROUND(IFNULL(aov, 0)) AS INT64))
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_country_level3
)

SELECT
  'WoW' AS report_type,

  /* period_label now matches dash_page_summary PAGE1_WOW:
     "2026-08-31 to 2026-09-06 vs 2026-08-24 to 2026-08-30" */
  CONCAT(CAST(w.wow_week_start AS STRING), ' to ', CAST(w.wow_through AS STRING),
         ' vs ', CAST(w.prv_wk_start AS STRING), ' to ', CAST(w.prv_wk_end AS STRING))
    AS period_label,

  CONCAT(
'You write board-level retail performance commentary for LSOUL (fashion retail; Vietnam, Thailand, China).\n',
'This is the Week-over-Week review. All figures are VND.\n\n',

'REPORTING WINDOW\n',
'  This week:  ', CAST(w.wow_week_start AS STRING), ' to ', CAST(w.wow_through AS STRING),
                  ' (day ', CAST(w.wtd_days_elapsed AS STRING), ' of 7)\n',
'  Prior week: ', CAST(w.prv_wk_start AS STRING), ' to ', CAST(w.prv_wk_end AS STRING), '\n\n',

'HARD RULES\n',
'1. Use ONLY the numbers supplied below. NEVER compute, re-derive, infer or estimate a number.\n',
'   Every figure you need - including the gap to target and the per-day rates - is already given.\n',
'2. If a fact is not supplied, say nothing about it. Refuse to speculate. Do not mention\n',
'   traffic, sessions, footfall, advertising spend or stock: none of it is supplied here.\n',
'3. Country names, level_1 channel types and level_3 platform and store names stay EXACTLY as\n',
'   written. Never translate or transliterate them (Shopee, TikTok, Xiaohongshu, VN Ecommerce).\n',
  IF(w.wtd_days_elapsed >= w.week_total_days,
    CONCAT(
'4. PERIOD COMPLETENESS. This week is COMPLETE: 7 days against the 7 days of the prior week.\n',
'   The WoW comparison is like-for-like and may be described as growth or decline.\n'),
    CONCAT(
'4. PERIOD COMPLETENESS - THIS WEEK IS PARTIAL.\n',
'   This week covers ', CAST(w.wtd_days_elapsed AS STRING), ' of 7 days. The prior-week figures\n',
'   below are a FULL 7 days. Every "change" number is therefore ',
     CAST(w.wtd_days_elapsed AS STRING), ' days measured against 7\n',
'   and is NOT like-for-like. Do NOT call any of it a decline, a drop or underperformance -\n',
'   most of the gap is days that have not been traded yet. Whenever you quote one of these\n',
'   figures, attach the words "', CAST(w.wtd_days_elapsed AS STRING), ' of 7 days vs a full prior week".\n')),
'5. Achievement is revenue this week over the FULL-week target. State it as a share of the\n',
'   week target at day ', CAST(w.wtd_days_elapsed AS STRING), ' of 7. Never as bare underperformance.\n\n',

'OVERALL\n',
'- Revenue this week: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.wow_revenue, 0)) AS INT64)), '\n',
'- Revenue prior week: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.prior_week_revenue, 0)) AS INT64)), '\n',
'- WoW change: ', IFNULL(CAST(ROUND(o.wow_growth * 100, 1) AS STRING), 'n/a'), '%\n',
'- Week target: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.wow_target, 0)) AS INT64)), '\n',
'- Achievement vs full-week target: ', IFNULL(CAST(ROUND(o.pct_achievement * 100, 1) AS STRING), 'n/a'), '%\n',
  /* gap_to_target is negative when the target is beaten. Printing that as
     "still needed: -1,769,912,787" invites the model to write a shortfall
     sentence about a week that came in 129% of target, so the sign decides the
     wording and required/day is suppressed once the target is met. */
  IF(o.gap_to_target > 0,
     CONCAT('- Still needed to reach the week target: ', FORMAT("%'d", CAST(ROUND(o.gap_to_target) AS INT64)), '\n'),
     CONCAT('- Week target already exceeded by: ', FORMAT("%'d", CAST(ROUND(-o.gap_to_target) AS INT64)), '\n')),
'- Days left in the week: ', CAST(o.days_left AS STRING), '\n',
'- Revenue per day achieved so far: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.achieved_daily,0)) AS INT64)), '\n',
'- Revenue per day required over the days left: ',
   CASE WHEN o.days_left <= 0        THEN 'n/a (week complete)'
        WHEN o.gap_to_target <= 0    THEN '0 (target already met)'
        ELSE FORMAT("%'d", CAST(ROUND(o.required_daily) AS INT64)) END, '\n',
'- Average Order Value: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.aov, 0)) AS INT64)), '\n\n',

'BY COUNTRY\n', IFNULL(cl.text, 'No data'), '\n\n',
'BY CHANNEL TYPE (level_1)\n', IFNULL(l1.text, 'No data'), '\n\n',
'BY CHANNEL (country / level_3)\n', IFNULL(chl.text, 'No data'), '\n\n',

'OUTPUT - return EXACTLY these three sections, in this order, and nothing else:\n',
'  SUMMARY   - one sentence on overall performance for this week. If the week is not complete,\n',
'              also state how much revenue is still needed to reach the week target and the\n',
'              per-day rate that implies over the days left. Both figures are supplied above.\n',
'  HIGHLIGHT - one sentence naming the strongest country and level_3 platform, with its figures.\n',
'  LOWLIGHT  - one sentence naming the weakest country and level_3 platform needing attention,\n',
'              with its figures.\n',
'Do NOT add any other section, category, heading, recommendation list or commentary.\n\n',

'LANGUAGE\n',
'Write all three sections in natural, professional Vietnamese with full diacritics - not a\n',
'word-for-word translation. Use standard retail trade vocabulary (doanh thu, chỉ tiêu, tiến độ,\n',
'giá trị đơn hàng trung bình, kênh bán, tăng trưởng). Numbers, country names and platform names\n',
'stay exactly as written above; do not localise digit separators.\n'
  ) AS prompt_text
FROM wow_pace o, wow_country_lines cl, wow_level1_lines l1, wow_channel_lines chl, wow_week w

;
/* =============================================================================
   v_ai_report_prompts is UNCHANGED and is not redefined here.

       SELECT * FROM v_mtd_prompt UNION ALL SELECT * FROM v_wow_prompt

   It still resolves, because both views keep the same three columns in the same
   order and types: report_type STRING, period_label STRING, prompt_text STRING.
   ========================================================================== */

   /* =============================================================================
   Post-deployment checks for v_mtd_prompt / v_wow_prompt.
   Run each block after deploying deploy_prompt_views.sql.
   ========================================================================== */

-- 1. OUTPUT CONTRACT. Must return exactly three rows, in this order:
--      report_type STRING (1), period_label STRING (2), prompt_text STRING (3)
--    for BOTH views, or v_ai_report_prompts breaks.
SELECT table_name, ordinal_position, column_name, data_type
FROM `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('v_mtd_prompt','v_wow_prompt')
ORDER BY table_name, ordinal_position;

-- 2. GRAIN. Must be exactly one row per view, two through the union.
SELECT report_type, COUNT(*) AS rows_out
FROM `marine-cycle-484213-b4.reportdb.v_ai_report_prompts`
GROUP BY 1 ORDER BY 1;

-- 3. PERIOD ALIGNMENT WITH THE DASHBOARD. The two period_label values must
--    match dash_page_summary exactly. A mismatch means the prompt views and the
--    dashboard are describing different windows on the same day.
SELECT
   pr.report_type
  ,pr.period_label                    AS prompt_label
  ,ps.period_label                    AS dashboard_label
  ,pr.period_label = ps.period_label  AS aligned
FROM `marine-cycle-484213-b4.reportdb.v_ai_report_prompts` pr
JOIN `marine-cycle-484213-b4.reportdb.dash_page_summary` ps
  ON ps.page = IF(pr.report_type = 'WoW', 'PAGE1_WOW', 'PAGE2_MTD')
ORDER BY pr.report_type;

-- 4. NO TODAY'S-DATE LEAKAGE. Both definitions must be free of CURRENT_DATE.
SELECT table_name,
       REGEXP_CONTAINS(view_definition, r'CURRENT_DATE') AS still_uses_current_date,
       REGEXP_CONTAINS(view_definition, r'dash_run_params') AS anchors_on_run_params
FROM `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.VIEWS`
WHERE table_name IN ('v_mtd_prompt','v_wow_prompt')
ORDER BY table_name;

-- 5. THREE INSIGHT TYPES AND NO MORE. The prompt must name SUMMARY, HIGHLIGHT
--    and LOWLIGHT and must not introduce another category. These are the words
--    fn_performance_snapshot_ai_generated_v2 expects back
--    (output_schema => 'summary STRING, highlights ARRAY<STRING>, lowlights ARRAY<STRING>').
SELECT report_type,
       REGEXP_CONTAINS(prompt_text, r'SUMMARY')                       AS has_summary,
       REGEXP_CONTAINS(prompt_text, r'HIGHLIGHT')                     AS has_highlight,
       REGEXP_CONTAINS(prompt_text, r'LOWLIGHT')                      AS has_lowlight,
       REGEXP_CONTAINS(prompt_text, r'(?i)\b(risk|opportunit|recommendation|action item)s?\b')
                                                                      AS leaked_extra_category,
       LENGTH(prompt_text)                                            AS prompt_chars
FROM `marine-cycle-484213-b4.reportdb.v_ai_report_prompts`
ORDER BY report_type;

-- 6. PERIOD-COMPLETENESS RULE FIRED THE RIGHT WAY. On a partial period the
--    prompt must carry the PARTIAL wording; on a complete one, COMPLETE.
--    Cross-check against dash_run_params rather than trusting the text.
SELECT
   pr.report_type
  ,p.report_date, p.mtd_days_elapsed, p.month_total_days
  ,DATE_DIFF(p.report_date, p.cur_wk_start, DAY) + 1 AS wtd_days_elapsed
  ,REGEXP_CONTAINS(pr.prompt_text, r'PERIOD COMPLETENESS - THIS')  AS says_partial
  ,REGEXP_CONTAINS(pr.prompt_text, r'PERIOD COMPLETENESS\. (This|The)') AS says_complete
FROM `marine-cycle-484213-b4.reportdb.v_ai_report_prompts` pr, `marine-cycle-484213-b4.reportdb.dash_run_params` p
ORDER BY pr.report_type;

-- 7. PHANTOM CHANNELS GONE. The period_date <= report_date guard should drop the
--    level_3 values that exist only on future-dated target rows with no actuals
--    (on the 2026-09-06 run: TQ Ecommerce, VN Ecommerce, VN Offline Store and
--    four more, all revenue 0). Expect zero rows here.
SELECT country, level_3, MIN(period_date) AS first_dt,
       CAST(ROUND(ANY_VALUE(monthly_revenue_by_country_level_3)) AS INT64) AS mtd_rev
FROM `marine-cycle-484213-b4.reportdb.performance_snapshot_v2_base` b,
     `marine-cycle-484213-b4.reportdb.dash_run_params` p
WHERE b.month_start = p.month_start
GROUP BY 1,2
HAVING MIN(period_date) > ANY_VALUE(p.report_date);

-- 8. EYEBALL. Read both prompts end to end once before trusting the output.
SELECT report_type, period_label, prompt_text
FROM `marine-cycle-484213-b4.reportdb.v_ai_report_prompts`
ORDER BY report_type;