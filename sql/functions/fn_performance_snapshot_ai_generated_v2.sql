CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_performance_snapshot_ai_generated_v2(i_type INT64, i_number_year_back INT64)
AS
WITH v_performance_base AS (
  SELECT DISTINCT
    period_date, week_start, month_start, country, level_1, level_2, level_3,

    -- Weekly
    weekly_sales_revenue, prev_weekly_sales_revenue,
    weekly_sales_revenue_by_country_level_3, prev_weekly_sales_revenue_country_level_3,
    weekly_sales_revenue_by_level_1, prev_weekly_sales_revenue_level_1,
    weekly_sales_revenue_by_level_2, prev_weekly_sales_revenue_level_2,
    target_revenue_weekly, pct_achievement_weekly, wow_growth_pct,
    aov_weekly, aov_weekly_country_level_3,

    -- Monthly
    monthly_sale_revenue, prev_monthly_sales_revenue,
    monthly_sales_revenue_by_country_level_3, prev_monthly_sales_revenue_country_level_3,
    target_revenue_monthly, pct_achievement_monthly, mom_growth_pct,

    -- Daily target (only used to build a full MTD target sum where needed)
    target_revenue_daily_country

  FROM `marine-cycle-484213-b4.reportdb.fn_performance_snapshot_v2`(
    0,                                           -- i_type: unused
    1,                                            -- i_number_year_back: 1, safely covers a Dec -> Jan week boundary
    DATE_SUB(CURRENT_DATE(), INTERVAL 45 DAY),   -- i_date_from: covers current MTD + last 2 weeks with margin
    DATE_SUB(CURRENT_DATE(),INTERVAL 1 DAY)                               -- i_date_to
  )
),


-- =========================================================================
-- 2. MTD prompt
-- =========================================================================
mtd_rows AS (
  SELECT *
  FROM v_performance_base
  WHERE month_start = DATE_TRUNC(CURRENT_DATE(), MONTH)
),

mtd_overall AS (
  SELECT
    ANY_VALUE(monthly_sale_revenue) AS mtd_revenue,
    ANY_VALUE(prev_monthly_sales_revenue) AS prior_month_revenue,
    ANY_VALUE(target_revenue_monthly) AS mtd_target,
    ANY_VALUE(pct_achievement_monthly) AS pct_achievement,
    ANY_VALUE(mom_growth_pct) AS mom_growth
  FROM mtd_rows
),

mtd_country_level3 AS (
  SELECT DISTINCT country, level_3,
    monthly_sales_revenue_by_country_level_3 AS revenue,
    prev_monthly_sales_revenue_country_level_3 AS prior_revenue
  FROM mtd_rows
),

mtd_by_country AS (
  SELECT country,
    SUM(IFNULL(revenue, 0)) AS revenue,
    SUM(IFNULL(prior_revenue, 0)) AS prior_revenue
  FROM mtd_country_level3
  GROUP BY 1
),

mtd_country_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ': revenue ', FORMAT("%'d", CAST(ROUND(revenue) AS INT64)),
      ', MoM change vs prior month: ',
      IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM mtd_by_country
),

mtd_channel_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ' / ', IFNULL(level_3, 'n/a'), ': revenue ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', MoM change: ',
      IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM mtd_country_level3
),

v_mtd_prompt AS (
SELECT
  'MTD' AS report_type,
  FORMAT_DATE('%B %Y', CURRENT_DATE()) AS period_label,
  CONCAT(
    'You are a retail performance analyst preparing a Month-to-Date business review ',
    'for LSOUL, a multi-country fashion retail brand operating in Vietnam, Thailand, and China. ',
    'All revenue figures are in VND (adjust this if your reporting currency differs).\n\n',
    'Reporting period: month-to-date for ', FORMAT_DATE('%B %Y', CURRENT_DATE()),
    ', data through ', CAST(CURRENT_DATE() AS STRING), '.\n\n',
    'OVERALL:\n',
    '- MTD revenue: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.mtd_revenue, 0)) AS INT64)), '\n',
    '- MTD target: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.mtd_target, 0)) AS INT64)), '\n',
    '- Achievement: ', IFNULL(CAST(ROUND(o.pct_achievement * 100, 1) AS STRING), 'n/a'), '%\n',
    '- MoM change vs prior month: ', IFNULL(CAST(ROUND(o.mom_growth * 100, 1) AS STRING), 'n/a'), '%\n\n',
    'BY COUNTRY:\n', IFNULL(cl.text, 'No data'), '\n\n',
    'BY CHANNEL (country / channel):\n', IFNULL(chl.text, 'No data'), '\n\n',
    'Based only on the figures above, provide:\n',
    '1. A concise 2-3 sentence executive summary of overall MTD performance.\n',
    '2. 3-5 highlights: the strongest performing countries/channels or positive trends.\n',
    '3. 3-5 lowlights: the weakest performing countries/channels or trends needing attention.\n',
    'Do not invent numbers that are not present in the data above.'
  ) AS prompt_text
FROM mtd_overall o, mtd_country_lines cl, mtd_channel_lines chl
),

-- =========================================================================
-- 3. WoW prompt (last fully completed week vs the week before it)
-- =========================================================================
wow_week AS (
  SELECT DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY)), INTERVAL 7 DAY) AS wow_week_start
),

wow_rows AS (
  SELECT b.*
  FROM v_performance_base b, wow_week w
  WHERE b.week_start = w.wow_week_start
),

wow_overall AS (
  SELECT
    ANY_VALUE(weekly_sales_revenue) AS wow_revenue,
    ANY_VALUE(prev_weekly_sales_revenue) AS prior_week_revenue,
    ANY_VALUE(target_revenue_weekly) AS wow_target,
    ANY_VALUE(pct_achievement_weekly) AS pct_achievement,
    ANY_VALUE(wow_growth_pct) AS wow_growth,
    ANY_VALUE(aov_weekly) AS aov
  FROM wow_rows
),

wow_country_level3 AS (
  SELECT DISTINCT country, level_3,
    weekly_sales_revenue_by_country_level_3 AS revenue,
    prev_weekly_sales_revenue_country_level_3 AS prior_revenue,
    aov_weekly_country_level_3 AS aov
  FROM wow_rows
),

wow_by_country AS (
  SELECT country,
    SUM(IFNULL(revenue, 0)) AS revenue,
    SUM(IFNULL(prior_revenue, 0)) AS prior_revenue
  FROM wow_country_level3
  GROUP BY 1
),

wow_by_level1 AS (
  SELECT DISTINCT level_1,
    weekly_sales_revenue_by_level_1 AS revenue,
    prev_weekly_sales_revenue_level_1 AS prior_revenue
  FROM wow_rows
),

wow_country_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ': revenue ', FORMAT("%'d", CAST(ROUND(revenue) AS INT64)),
      ', WoW change: ',
      IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_by_country
),

wow_level1_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', level_1, ': revenue ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', WoW change: ',
      IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%'
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_by_level1
),

wow_channel_lines AS (
  SELECT STRING_AGG(
    CONCAT(
      '- ', country, ' / ', IFNULL(level_3, 'n/a'), ': revenue ', FORMAT("%'d", CAST(ROUND(IFNULL(revenue, 0)) AS INT64)),
      ', WoW change: ',
      IFNULL(CAST(ROUND(SAFE_DIVIDE(revenue - prior_revenue, NULLIF(prior_revenue, 0)) * 100, 1) AS STRING), 'n/a'), '%',
      ', AOV: ', FORMAT("%'d", CAST(ROUND(IFNULL(aov, 0)) AS INT64))
    ), '\n' ORDER BY revenue DESC
  ) AS text
  FROM wow_country_level3
),

v_wow_prompt AS (
  SELECT
    'WoW' AS report_type,
    CONCAT('Week of ', CAST(w.wow_week_start AS STRING)) AS period_label,
    CONCAT(
      'You are a retail performance analyst preparing a Week-over-Week business review ',
      'for LSOUL, a multi-country fashion retail brand operating in Vietnam, Thailand, and China. ',
      'All revenue figures are in VND (adjust this if your reporting currency differs).\n\n',
      'Reporting period: the week starting ', CAST(w.wow_week_start AS STRING),
      ' (last fully completed week), compared to the week before it.\n\n',
      'OVERALL:\n',
      '- Weekly revenue: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.wow_revenue, 0)) AS INT64)), '\n',
      '- Weekly target: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.wow_target, 0)) AS INT64)), '\n',
      '- Achievement: ', IFNULL(CAST(ROUND(o.pct_achievement * 100, 1) AS STRING), 'n/a'), '%\n',
      '- WoW change vs prior week: ', IFNULL(CAST(ROUND(o.wow_growth * 100, 1) AS STRING), 'n/a'), '%\n',
      '- Average Order Value: ', FORMAT("%'d", CAST(ROUND(IFNULL(o.aov, 0)) AS INT64)), '\n\n',
      'BY COUNTRY:\n', IFNULL(cl.text, 'No data'), '\n\n',
      'BY CHANNEL TYPE:\n', IFNULL(l1.text, 'No data'), '\n\n',
      'BY CHANNEL (country / channel):\n', IFNULL(chl.text, 'No data'), '\n\n',
      'Based only on the figures above, provide:\n',
      '1. A concise 2-3 sentence executive summary of overall weekly performance.\n',
      '2. 3-5 highlights: the strongest performing countries/channels or positive trends.\n',
      '3. 3-5 lowlights: the weakest performing countries/channels or trends needing attention.\n',
      'Do not invent numbers that are not present in the data above.'
    ) AS prompt_text
  FROM wow_overall o, wow_country_lines cl, wow_level1_lines l1, wow_channel_lines chl, wow_week w
)

-- =========================================================================
-- 4. Combine MTD + WoW prompts into a single 2-row dataset
-- =========================================================================
,v_ai_report_prompts AS (
SELECT * FROM v_mtd_prompt
UNION ALL
SELECT * FROM v_wow_prompt
)

-- =========================================================================
-- 5. Generate the AI insights (summary / highlights / lowlights)
--    Re-run just this statement on a schedule to refresh.
-- =========================================================================
,ai_generated AS (
  SELECT
    report_type,
    period_label,
    prompt_text,
    AI.GENERATE(
      prompt_text,
      -- connection_id => 'us.your_vertex_connection',  -- uncomment + set if not using end-user credentials
      endpoint       => 'gemini-2.5-pro',
      output_schema  => 'summary STRING, highlights ARRAY<STRING>, lowlights ARRAY<STRING>'
    ) AS ai_result
  FROM v_ai_report_prompts
)


SELECT
  report_type,
  period_label,
  ai_result.summary    AS summary,
  ai_result.highlights AS highlights,
  ai_result.lowlights  AS lowlights,
  CURRENT_TIMESTAMP()  AS generated_at
FROM ai_generated;
