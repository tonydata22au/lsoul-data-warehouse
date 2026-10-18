/* =============================================================================
   Post-deploy smoke test  --  run AFTER the Dataform run, BEFORE sp_dash_run_dashboard
   -----------------------------------------------------------------------------
   Every check returns PASS or FAIL with the number that decided it. Nothing here
   writes. Run it as one script and read the verdict column.
   ========================================================================== */

-- 1. Corrected ads source matches the raw platform tables for the reporting week.
--    This is the check that would have caught the 4.5x TikTok fan-out.
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
fn AS (
  SELECT SUM(spend) AS spend, SUM(reach) AS reach, SUM(clicks) AS clicks
  FROM `marine-cycle-484213-b4.reportdb.dash_base_ads_day` d CROSS JOIN p
  WHERE d.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end
),
raw AS (
  SELECT SUM(spend) AS spend, SUM(reach) AS reach, SUM(clicks) AS clicks FROM (
    SELECT amount_spend AS spend, reach, clicks FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_a` a
      CROSS JOIN p WHERE a.day BETWEEN p.cur_wk_start AND p.cur_wk_end AND a.campaign_type IS NOT NULL
    UNION ALL
    SELECT amount_spend, reach, clicks FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_my` a
      CROSS JOIN p WHERE a.day BETWEEN p.cur_wk_start AND p.cur_wk_end AND a.campaign_type IS NOT NULL
    UNION ALL
    SELECT spend, reach, clicks FROM `marine-cycle-484213-b4.core_tiktok.core_reporting_basic_auction_ad` t
      CROSS JOIN p WHERE t.inserted_at BETWEEN p.cur_wk_start AND p.cur_wk_end
    UNION ALL
    SELECT cost, NULL, NULL FROM `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report` t
      CROSS JOIN p WHERE t.inserted_at BETWEEN p.cur_wk_start AND p.cur_wk_end
    UNION ALL
    SELECT total_spend, NULL, total_clicks FROM `marine-cycle-484213-b4.reportdb.fn_ads_spend_ggads`(0) g
      CROSS JOIN p WHERE g.day BETWEEN p.cur_wk_start AND p.cur_wk_end
  )
)
SELECT '1. ads spend reconciles to raw' AS check_name,
       IF(ABS(fn.spend - raw.spend) < 1, 'PASS', 'FAIL') AS verdict,
       FORMAT('base %.1fm vs raw %.1fm', fn.spend/1e6, raw.spend/1e6) AS detail
FROM fn, raw

UNION ALL
-- 2. Level_3 week targets still sum to the level_2 plan (the fn_order_target_master trap).
SELECT '2. weekly target allocation reconciles',
       IF(COUNTIF(ABS(alloc - tgt) > 1) = 0, 'PASS', 'FAIL'),
       FORMAT('%d channel-weeks off', COUNTIF(ABS(alloc - tgt) > 1))
FROM (
  SELECT week_start, country, level_2,
         SUM(week_target) AS alloc, MAX(week_target_level_2) AS tgt
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
  WHERE week_target_level_2 IS NOT NULL
  GROUP BY 1,2,3
)

UNION ALL
-- 3. The prompt carries the new blocks and the SCOPED traffic rule, not the old blanket one.
SELECT '3. prompt has scoped traffic rule',
       IF(LOGICAL_AND(REGEXP_CONTAINS(prompt, r'TRAFFIC AND PAID MEDIA')
                  AND REGEXP_CONTAINS(prompt, r'FOOTFALL DOES NOT EXIST')
                  AND NOT REGEXP_CONTAINS(prompt, r'Traffic and footfall data DO NOT EXIST')),
          'PASS', 'FAIL'),
       FORMAT('%d pages checked', COUNT(*))
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts`

UNION ALL
-- 4. Marketing facts actually reached the prompt (or correctly said there were none).
SELECT '4. marketing block populated',
       IF(LOGICAL_AND(REGEXP_CONTAINS(facts_block,
            r'(roas_channel|no paid media or website traffic recorded)')), 'PASS', 'FAIL'),
       FORMAT('%d pages', COUNT(*))
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts`

UNION ALL
-- 5. Point ids are unique and well formed across BOTH series.
SELECT '5. point ids unique and well formed',
       IF(COUNT(*) = COUNT(DISTINCT point_id)
          AND COUNTIF(NOT REGEXP_CONTAINS(point_id, r'^[PM][0-9]{2}$')) = 0, 'PASS', 'FAIL'),
       FORMAT('%d trade, %d marketing',
              COUNTIF(point_type='TRADE'), COUNTIF(point_type='MARKETING'))
FROM `marine-cycle-484213-b4.reportdb.dash_material_points`

--select * FROM `marine-cycle-484213-b4.reportdb.dash_material_points`

UNION ALL
-- 6. No channel is flagged for pace on days it was never read (the R3 gate).
SELECT '6. no pace call on incomplete data',
       IF(COUNTIF(r3_pace AND NOT is_month_data_complete) = 0, 'PASS', 'FAIL'),
       FORMAT('%d violations', COUNTIF(r3_pace AND NOT is_month_data_complete))
FROM `marine-cycle-484213-b4.reportdb.dash_material_points`

UNION ALL
-- 7. Traffic reconciles: sessions in the base table equal GA4 for the week.
SELECT '7. website sessions reconcile to GA4',
       IF(ABS(b.s - g.s) = 0, 'PASS', 'FAIL'),
       FORMAT('base %d vs GA4 %d', b.s, g.s)
FROM (SELECT SUM(sessions) AS s FROM `marine-cycle-484213-b4.reportdb.dash_base_traffic_day` d
      CROSS JOIN p WHERE d.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end) b,
     (SELECT SUM(sessions) AS s
      FROM `marine-cycle-484213-b4.reportdb.fn_marketing_website_traffic_analysis`() t
      CROSS JOIN p WHERE DATE(t.event_timestamp) BETWEEN p.cur_wk_start AND p.cur_wk_end) g

ORDER BY check_name;