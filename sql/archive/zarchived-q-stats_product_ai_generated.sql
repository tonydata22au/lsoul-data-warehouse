
/*
Author: Toan Pham
Date: 00/08/2026
Comment: 
*/

WITH
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
FROM ai_generated