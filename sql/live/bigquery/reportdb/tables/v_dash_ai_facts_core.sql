CREATE VIEW `marine-cycle-484213-b4.reportdb.v_dash_ai_facts_core`
OPTIONS(
  description="Builds the model prompt: hard rules, trend series, material points, TRAFFIC AND PAID MEDIA, and now SUB-CHANNEL DRIVERS at level_3. HARD RULE 3 gains clause (d): the level_2 media block does not attribute to a level_3."
)
AS WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`), 

common AS (
  SELECT CONCAT(
'You write board-level retail performance commentary for LSOUL (fashion retail; Vietnam, Thailand, China).\n',
'Return FOUR fields: exec_summary_en, exec_summary_vi, highlights_en, highlights_vi, actions_vi.\n\n',
'HARD RULES (apply to every field, both languages):\n',
'1. Use ONLY the supplied numbers. NEVER compute, re-derive, infer or estimate any number.\n',
'2. Numbers identical across languages - same digits, signs and units. Do not localise separators.\n',
'3. TRAFFIC AND PAID MEDIA. Website traffic and paid-media figures ARE supplied, in the\n',
'   TRAFFIC AND PAID MEDIA block, and ONLY for the channels listed there. You may state that\n',
'   traffic or spend moved only by quoting a number from that block.\n',
'   Four limits on it, all absolute:\n',
'   (a) The traffic figures are WEBSITE sessions only. FOOTFALL DOES NOT EXIST for any\n',
'       physical store. Never explain a store movement with visits, traffic or footfall.\n',
'   (b) A channel absent from that block has NO traffic or spend data. Say nothing about its\n',
'       traffic or spend - not even that it is unknown.\n',
'   (c) roas_channel is revenue divided by spend for that channel. It is an efficiency ratio,\n',
'       NOT proof the spend caused the revenue. Never write that spend "drove", "generated"\n',
'       or "delivered" revenue. Write that the channel returned X per VND spent.\n',
'   (d) SUB-CHANNEL GRAIN. The TRAFFIC AND PAID MEDIA block is per market and channel\n',
'       (level_2). The SUB-CHANNEL DRIVERS block goes one level deeper, to the platform or\n',
'       store (level_3), and is the ONLY place you may attribute media to a sub-channel.\n',
'       Where a driver line says no media targets that sub-channel, you must NOT explain its\n',
'       move with the channel-level spend above - treat it as a trade movement and say so.\n',
'4. If a fact is not supplied, say nothing about it. Refuse to speculate.\n',
'5. DATA COMPLETENESS. Where a line is marked INCOMPLETE, the figures cover only the days\n',
'   listed. Do not describe such a channel as down, behind or underperforming - the reading\n',
'   is a reporting gap, not a trading result. Say the data is incomplete and state through\n',
'   which date it runs.\n\n',
'MATERIALITY - this is the core editorial rule:\n',
'6. The MATERIAL POINTS list below has ALREADY been filtered in SQL. Write about those points\n',
'   and NOTHING else. Do not mention a channel that is not in the list, however large it looks\n',
'   in the trend series - if it is not listed, it did not clear the threshold and the board\n',
'   should not see it.\n',
'7. CONSISTENCY: EVERY point in the list must be covered in exec_summary AND in\n',
'   highlights/lowlights. Do not drop a point because it seems minor - it is in the list\n',
'   precisely because it cleared the threshold. If there are more points than sentences you\n',
'   are allowed, group several into one sentence rather than omitting any.\n',
'   Cite each point by its ID (P01, P02... for trade, M01, M02... for marketing) at the end\n',
'   of the sentence that covers it.\n',
'   A point covered in one field but missing from another is a failure.\n\n',
'EXEC SUMMARY - 3 to 5 sentences, in this exact order:\n',
'   a) last week versus the prior week (WoW)\n',
'   b) current month-to-date performance\n',
'   c) progress against the monthly target INCLUDING pace, phrased like\n',
'      "62% of target at day 18 of 31"\n',
'      For pace you MUST use ATTAINMENT vs FULL-MONTH target, never the pro-rated MTD\n',
'      attainment. They are different numbers: pairing the pro-rated figure with "day N of M"\n',
'      states the opposite of the truth. The pace verdict is supplied - reproduce it, do not\n',
'      re-derive it.\n',
'   Use the trend series to say whether a move continues or breaks an existing direction.\n',
'   If any MARKETING point (M##) exists, one of the sentences must cover paid media.\n\n',
'LANGUAGE RULES:\n',
'A. Section headings stay ENGLISH in both versions: "**Highlight -**", "**Lowlight -**", "ACTIONS:".\n',
'B. Channel identifiers, store names and SKU codes stay EXACTLY as written. Never translate them.\n',
'C. Owner tags in [brackets] stay EXACTLY as written. Never translate them.\n',
'D. Vietnamese must be natural, professional retail / e-commerce business Vietnamese with full\n',
'   diacritics - NOT word-for-word translation. Use standard trade vocabulary (doanh thu, hóa đơn,\n',
'   giá trị giỏ hàng, tồn kho, tỷ lệ bán ra, chỉ tiêu, tiến độ, tốc độ bán, chi phí quảng cáo,\n',
'   lượt truy cập, lượt nhấp).\n',
'E. You do NOT rewrite the English actions - they are final and appended from SQL.\n',
'   Return actions_vi only: translate each action line, keeping the [Owner] tag, every number,\n',
'   every SKU code and every store / platform name EXACTLY. Same count, same order.\n\n') AS r
),

/* compact sparkline: 8 prior weeks, oldest to newest.

   ONE unit for the whole series, chosen from the series maximum, and stated on
   the line. Auto-scaling each value independently would put "2.2,980.0,1.5" in
   one list - three magnitudes, no comparability. Fixing every series at mVND was
   the old behaviour and printed 2170 in an mVND list once a channel passed a
   billion a week, which is what this whole change is fixing. */
spark_src AS (
  SELECT week_start, country, level_2, SUM(nmv) AS nmv, SUM(bills) AS bills
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly` t 
  CROSS JOIN p WHERE NOT t.is_current_week
  GROUP BY 1,2,3
),
spark_scale AS (
  SELECT country, level_2
        ,GREATEST(IFNULL(`marine-cycle-484213-b4.reportdb.fn_money_scale`(CAST(MAX(ABS(nmv)) AS FLOAT64)), 1), 1) AS s
        ,`marine-cycle-484213-b4.reportdb.fn_money_unit`(CAST(MAX(ABS(nmv)) AS FLOAT64))                          AS u
  FROM spark_src GROUP BY 1,2
),
spark_w AS (
  SELECT sr.country, sr.level_2, sc.u AS nmv_unit,
    STRING_AGG(FORMAT('%.1f', CAST(sr.nmv AS FLOAT64)/sc.s), ',' ORDER BY sr.week_start) AS nmv_series,
    STRING_AGG(FORMAT('%d', sr.bills),                       ',' ORDER BY sr.week_start) AS bills_series
  FROM spark_src sr
  JOIN spark_scale sc ON sc.country = sr.country AND sc.level_2 = sr.level_2
  GROUP BY 1,2,3
),
spark_m AS (
  SELECT country, level_2,
    STRING_AGG(FORMAT('%s:%s%%', FORMAT_DATE('%b', DATE(month_start)),
        IFNULL(FORMAT('%.0f', attainment_vs_full_month*100),'n/a')), ' ' ORDER BY month_start) AS attain_series
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
  WHERE NOT is_low_target AND NOT is_target_invalid
  GROUP BY country, level_2
),
trend_block AS (
  SELECT STRING_AGG(
    FORMAT('%s / %s | NMV 8wk (%s): %s | bills 8wk: %s | monthly attainment: %s',
      s.country, s.level_2, s.nmv_unit, s.nmv_series, s.bills_series, IFNULL(sm.attain_series,'no target')),
    '\n' ORDER BY s.country, s.level_2) AS block
  FROM spark_w s LEFT JOIN spark_m sm USING (country, level_2)
),

-- Only channels that actually carry spend or sessions appear, so HARD RULE
-- 3(b) has something concrete to point at: absence from this block means the
-- model has no traffic or spend data for that channel and must stay silent.
marketing_block AS (
  SELECT IFNULL(STRING_AGG(line, '\n' ORDER BY sort_spend DESC), '') AS block
  FROM (
    SELECT
       SUM(m.spend) AS sort_spend
      ,FORMAT('%s / %s | spend %s (%s%% WoW) | delivery %s | clicks %s | roas_channel %s (%s%% WoW) | cost of sale %s%%%s',
         m.country, m.level_2,
         `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(SUM(m.spend) AS FLOAT64)),
         IFNULL(FORMAT('%.0f', SAFE_DIVIDE(SUM(m.spend), NULLIF(SUM(m.spend_prev_wk),0)) * 100 - 100), 'n/a'),
         IFNULL(FORMAT('%d', SUM(m.delivery)), 'n/a'),
         IFNULL(FORMAT('%d', SUM(m.clicks)), 'n/a'),
         IFNULL(FORMAT('%.1f', SAFE_DIVIDE(SUM(m.nmv), NULLIF(SUM(m.spend),0))), 'n/a'),
         IFNULL(FORMAT('%.0f', SAFE_DIVIDE(
             SAFE_DIVIDE(SUM(m.nmv), NULLIF(SUM(m.spend),0)),
             NULLIF(SAFE_DIVIDE(SUM(m.nmv_prev_wk), NULLIF(SUM(m.spend_prev_wk),0)),0)) * 100 - 100), 'n/a'),
         IFNULL(FORMAT('%.0f', SAFE_DIVIDE(SUM(m.spend), NULLIF(SUM(m.nmv),0)) * 100), 'n/a'),
         IF(SUM(m.sessions) > 0,
            FORMAT(' | WEBSITE sessions %d (%s%% WoW), paid share %s%%, new-visitor share %s%%',
              SUM(m.sessions),
              IFNULL(FORMAT('%.0f', SAFE_DIVIDE(SUM(m.sessions), NULLIF(SUM(m.sessions_prev_wk),0)) * 100 - 100), 'n/a'),
              IFNULL(FORMAT('%.0f', SAFE_DIVIDE(SUM(m.paid_sessions), NULLIF(SUM(m.sessions),0)) * 100), 'n/a'),
              IFNULL(FORMAT('%.0f', SAFE_DIVIDE(SUM(m.new_visitor_sessions), NULLIF(SUM(m.sessions),0)) * 100), 'n/a')),
            '')
       ) AS line
    FROM `marine-cycle-484213-b4.reportdb.dash_trend_marketing_weekly` m 
    WHERE m.is_current_week AND (m.spend > 0 OR m.sessions > 0)
    GROUP BY m.country, m.level_2
  )
),

/* NEW. Sub-channel drivers, from dash_action_context, one line per material item
   on the page. Compact on purpose: the trade figures are already in MATERIAL
   POINTS, so this carries only what is new - which level_3 moved, whether media
   reaches it, and that media's own figures.

   The verdict is spelled out in words rather than as its token, and no causal
   verb appears, so a model that mirrors the phrasing stays inside
   det_causal_claim_ok. */
driver_block AS (
  SELECT page, STRING_AGG(line, '\n' ORDER BY sort_key DESC) AS block
  FROM (
    SELECT
       c.page
      ,ABS(c.impact_vnd) AS sort_key
      /* The sub-channel figure is page-specific, and mixing the two reads as
         nonsense. On PAGE1 impact_vnd is a week-on-week NMV delta, so the
         level_3 contribution is a share OF it. On PAGE2 impact_vnd is the MTD
         GAP TO TARGET - a level_3 delta is not a share of a gap, and printing
         "+103 mVND of -12352 mVND" invites exactly the wrong reading. PAGE2
         therefore states the sub-channel's own same-period MTD move instead. */
      ,FORMAT('%s / %s | %s | %s | %s%s%s',
         c.country, c.level_2, c.item_type,
         IF(c.page='PAGE1_WOW',
            FORMAT('sub-channel %s: %s of the %s weekly move',
              IFNULL(c.level_3,'(unattributed)'),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money`(c.driver_level_3_delta),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money`(c.impact_vnd)),
            FORMAT('sub-channel %s: MTD NMV moved %s (%s%%) vs the same days last month; channel gap to target %s',
              IFNULL(c.level_3,'(unattributed)'),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money`(c.sp_l3_nmv_delta),
              FORMAT('%.0f', IFNULL(c.sp_l3_nmv_pct,0)*100),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money`(c.impact_vnd))),
         CASE c.traffic_verdict
           WHEN 'SPEND_UP_CLICKS_DOWN'         THEN 'spend held or rose while clicks fell'
           WHEN 'PAID_TRAFFIC_DOWN'            THEN 'clicks fell'
           WHEN 'SITE_TRAFFIC_DOWN'            THEN 'website sessions fell'
           WHEN 'TRAFFIC_UP_CONVERSION_DOWN'   THEN 'clicks rose while revenue fell'
           WHEN 'TRAFFIC_HELD_CONVERSION_DOWN' THEN 'traffic broadly held'
           WHEN 'PAID_TRAFFIC_UP'              THEN 'clicks rose'
           WHEN 'GROWTH_WITHOUT_SPEND'         THEN 'growth alongside flat or lower spend'
           WHEN 'MEDIA_NOT_AT_THIS_LEVEL_3'    THEN 'NO paid media targets this sub-channel - treat as a trade movement'
           WHEN 'MEDIA_TOO_SMALL_TO_READ'      THEN 'media volume too small to read - treat as a trade movement'
           WHEN 'NOT_INSTRUMENTED'             THEN 'NO media or session data for this sub-channel - treat as a trade movement'
           ELSE 'traffic and revenue moved in different directions'
         END,
         IF(c.media_readable,
            FORMAT(' | %s spend %s (%s%%), clicks %d->%d (%s%%), CPC %s',
              IFNULL(c.attention_ads_channel,'paid'),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(c.attention_spend_prv, c.attention_spend_cur),
              FORMAT('%.0f', IFNULL(c.attention_spend_pct,0)*100),
              CAST(IFNULL(c.attention_clicks_prv,0) AS INT64),
              CAST(IFNULL(c.attention_clicks_cur,0) AS INT64),
              FORMAT('%.0f', IFNULL(c.attention_clicks_pct,0)*100),
              `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(c.attention_cpc_prv, c.attention_cpc_cur)),
            ''),
         IF(c.has_site_traffic,
            FORMAT(' | WEBSITE sessions %d->%d (%s%%)',
              CAST(IFNULL(c.sessions_prv,0) AS INT64),
              CAST(IFNULL(c.sessions_cur,0) AS INT64),
              FORMAT('%.0f', IFNULL(c.sessions_pct,0)*100)),
            '')
       ) AS line
    FROM `marine-cycle-484213-b4.reportdb.dash_action_context` c 
  ) GROUP BY page
),

points_block AS (
  SELECT STRING_AGG(line, '\n' ORDER BY point_id) AS block
  FROM (
    SELECT point_id,
      CASE WHEN point_type = 'MARKETING' THEN
        FORMAT('%s | MARKETING | %s / %s | spend %s (%s%%) | roas_channel %s->%s (%s%%) | sessions %s->%s (%s%%) | platforms %s | WHY: %s',
          point_id,
          country, level_2,
          `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(CAST(spend_p AS FLOAT64), CAST(spend AS FLOAT64)),
          FORMAT('%.0f', IFNULL(pct_spend,0)*100),
          IFNULL(FORMAT('%.1f', roas_p),'n/a'), IFNULL(FORMAT('%.1f', roas_channel),'n/a'),
          FORMAT('%.0f', IFNULL(pct_roas,0)*100),
          IFNULL(FORMAT('%d', sessions_p),'n/a'), IFNULL(FORMAT('%d', sessions),'n/a'),
          FORMAT('%.0f', IFNULL(pct_sessions,0)*100),
          IFNULL(ads_channels,'n/a'),
          material_reason)
      ELSE
        FORMAT('%s | %s | %s / %s | NMV %s (%s, %s%%) | bills %d->%d (%s%%) | AOV %s (%s%%) | UPT %s | MTD %s of %s, %s%% at %s%% elapsed, pace %spp | 8wk range %s | z %s | %s | WHY: %s',
          point_id, item_type, country, level_2,
          `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(CAST(nmv_p AS FLOAT64), CAST(nmv AS FLOAT64)),
          `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(delta_nmv AS FLOAT64)), FORMAT('%.0f', IFNULL(pct_nmv,0)*100),
          bills_p, bills, FORMAT('%.0f', IFNULL(pct_bills,0)*100),
          `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(CAST(aov_p AS FLOAT64), CAST(aov AS FLOAT64)), FORMAT('%.0f', IFNULL(pct_aov,0)*100),
          FORMAT('%.1f', IFNULL(units_per_bill,0)),
          `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(mtd_nmv AS FLOAT64)), `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(month_target AS FLOAT64)),
          IFNULL(FORMAT('%.0f', attainment_vs_full_month*100),'n/a'),
          FORMAT('%.0f', IFNULL(expected_pace,0)*100),
          IFNULL(FORMAT('%.0f', pace_gap_pp),'n/a'),
          `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(CAST(nmv_min_8wk AS FLOAT64), CAST(nmv_max_8wk AS FLOAT64)),
          IFNULL(FORMAT('%.1f', nmv_zscore_8wk),'n/a'),
          IF(is_month_data_complete, 'MTD COMPLETE', 'MTD INCOMPLETE - do not judge pace'),
          material_reason)
      END AS line
    FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
  )
),

/* Three renderings of the same actions.

   action_block      - English shown to the model and concatenated into
                       narrative_en. Since 2026-09-06 this is the model's prose.
   action_block_vi   - Vietnamese, already written by gemini-3.5-flash in
                       dash_action_items and already guarded there. This is what
                       the report renders.
   action_block_sql  - the deterministic SQL spine. NOT shown to anyone: it
                       exists so facts_hash is stable.

   The hash MUST use the spine. facts_hash decides whether sp_dash_generate_ai
   regenerates a page, and the model rewords the actions slightly on every run.
   Hashing the reworded English would change the hash on all ~17 runs a week and
   regenerate both page narratives every single time - turning the cache off and
   multiplying the most expensive action in the pipeline. The spine only changes
   when a FIGURE changes, which is exactly when a regeneration is warranted. */
acts AS (
  SELECT pg.page,
         STRING_AGG(a.action_item,     '\n' ORDER BY a.section, a.action_no) AS action_block,
         STRING_AGG(a.action_item_vi,  '\n' ORDER BY a.section, a.action_no) AS action_block_vi,
         STRING_AGG(CONCAT('[', a.owner, '] - ', a.action_text_sql),
                                       '\n' ORDER BY a.section, a.action_no) AS action_block_sql
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

-- Names the channels the completeness cutoff is holding back, and how much,
-- so HARD RULE 5 is enforceable rather than aspirational.
dq AS (
  SELECT IFNULL(STRING_AGG(
    FORMAT('%s / %s | complete only through %s | %s of %s days read | %s loaded but withheld',
      country, level_2, CAST(data_complete_through AS STRING),
      CAST(days_covered AS STRING), CAST(days_elapsed AS STRING),
      `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(nmv_excluded_by_cutoff AS FLOAT64))),
    '\n' ORDER BY nmv_excluded_by_cutoff DESC), '') AS block
  FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
  WHERE is_current_month AND NOT is_month_data_complete
),

pages AS (
  SELECT
     s.page
    ,s.period_label
    ,CONCAT(
       CASE s.page
         WHEN 'PAGE1_WOW' THEN CONCAT(
           'PAGE: Week over Week. PERIOD: ', s.period_label, '\n',
           'TOTAL: NMV ', `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(CAST(s.headline_reference AS FLOAT64), CAST(s.headline_actual AS FLOAT64)), ' (',
           FORMAT('%.0f', s.headline_pct*100), '%), ', CAST(s.bills AS STRING), ' bills.\n')
         ELSE CONCAT(
           'PAGE: Month to Date vs Target. PERIOD: ', s.period_label, '\n',
           'TOTAL MTD actual: ', `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(s.headline_actual AS FLOAT64)), '\n',
           'ATTAINMENT vs PRO-RATED MTD target (', `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(s.headline_reference AS FLOAT64)),
             '): ', FORMAT('%.0f', s.headline_pct*100), '%  <- headline attainment\n',
           'ATTAINMENT vs FULL-MONTH target (', `marine-cycle-484213-b4.reportdb.fn_fmt_money`(CAST(tot.full_month_target AS FLOAT64)),
             '): ', FORMAT('%.0f', tot.attain_full_month*100), '%  <- USE THIS ONE FOR PACE\n',
           'ELAPSED: day ', CAST(tot.days_elapsed AS STRING), ' of ', CAST(tot.days_total AS STRING),
             ' = ', FORMAT('%.0f', tot.elapsed_share*100), '%\n',
           'PACE: ', FORMAT('%.0f', tot.pace_gap_pp), 'pp -> ', tot.pace_verdict, '\n',
           'HEADLINE CAVEAT (state verbatim once at the end): ', s.headline_note, '\n')
       END,
       'DATA NOTE: ', s.data_as_of_note, '\n\n',
       'TREND SERIES (8 prior weeks, oldest first, unit stated per line; and last 6 months attainment):\n',
       tb.block, '\n\n',
       'TRAFFIC AND PAID MEDIA (reporting week, per market and channel; channels not listed have NO such data):\n',
       IFNULL(NULLIF(mb.block,''), '(no paid media or website traffic recorded this week)'), '\n\n',
       'SUB-CHANNEL DRIVERS (level_3; the ONLY place media may be attributed to a sub-channel - HARD RULE 3d):\n',
       IFNULL(NULLIF(db.block,''), '(no sub-channel driver resolved this period)'), '\n\n',
       'INCOMPLETE DATA (HARD RULE 5 applies to these channels):\n',
       IFNULL(NULLIF(dqb.block,''), '(all channels complete)'), '\n\n',
       'MATERIAL POINTS (already filtered - write about THESE ONLY):\n',
       IFNULL(pb.block, '(no points cleared the materiality thresholds this period)')
     ) AS facts_block
    ,IFNULL(a.action_block, '')     AS action_block
    ,IFNULL(a.action_block_vi, '')  AS action_block_vi
    ,IFNULL(a.action_block_sql, '') AS action_block_sql
  FROM sm s
  CROSS JOIN trend_block tb
  CROSS JOIN points_block pb
  CROSS JOIN marketing_block mb
  CROSS JOIN dq dqb
  CROSS JOIN tot
  LEFT JOIN acts a ON a.page = s.page
  LEFT JOIN driver_block db ON db.page = s.page
)
,base AS (
SELECT
   pg.page
  ,pg.period_label
  ,REPLACE(pg.period_label, ' ', '') AS period_key
  ,TO_HEX(MD5(CONCAT(pg.facts_block, '||', pg.action_block_sql))) AS facts_hash
  ,CONCAT(c.r, pg.facts_block,
     '\n\nACTIONS TO TRANSLATE (return in actions_vi, same order):\n', pg.action_block,
     '\n\nexec_summary: 3-5 sentences, order a) WoW b) MTD c) target progress with pace.',
     ' highlights_en / highlights_vi: one sentence per material point, tagged with its point ID.'
   ) AS prompt
  ,pg.facts_block
  ,pg.action_block
  ,pg.action_block_vi
  ,pg.action_block_sql
FROM pages pg CROSS JOIN common c
)
,guide AS (
  SELECT pg.page,
         STRING_AGG(CONCAT('- ', g.guidance_text), '\n' ORDER BY g.guidance_version) AS guidance_block,
         MAX(g.guidance_version) AS guidance_version
  FROM (SELECT 'PAGE1_WOW' AS page UNION ALL SELECT 'PAGE2_MTD') pg
  LEFT JOIN `marine-cycle-484213-b4.reportdb.dash_ai_guidance` g 
    ON g.is_active AND (g.page = pg.page OR g.page = 'BOTH')
  GROUP BY pg.page
)
SELECT
   b.page, b.period_label, b.period_key
  -- guidance version participates in the hash, so changing guidance regenerates
  ,TO_HEX(MD5(CONCAT(b.facts_block, '||', b.action_block_sql, '||',
                     IFNULL(gd.guidance_block,''), '||v', CAST(IFNULL(gd.guidance_version,0) AS STRING)))) AS facts_hash
  ,CONCAT(
     IF(gd.guidance_block IS NULL, '',
        CONCAT('LEARNED STYLE GUIDANCE (from reviewer feedback). Apply where it does not conflict\n',
               'with the HARD RULES below. The HARD RULES always win:\n', gd.guidance_block, '\n\n')),
     b.prompt
   ) AS prompt
  ,b.facts_block, b.action_block, b.action_block_vi, b.action_block_sql
  ,IFNULL(gd.guidance_version, 0) AS guidance_version
FROM base b
LEFT JOIN guide gd ON gd.page = b.page;
