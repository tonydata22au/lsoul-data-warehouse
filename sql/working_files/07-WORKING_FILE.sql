/* =============================================================================
   LSOUL DASHBOARD -- OBJECT CATALOG AND INSPECTION SCRIPT
   Project/dataset: marine-cycle-484213-b4.reportdb

   32 tables/views + 5 stored procedures, created by the six numbered scripts.
   Each section below states what an object is FOR, then gives a SELECT * you can
   run on its own. Large tables carry a LIMIT so a stray full scan cannot cost you.

   Naming convention:
     dash_*    physical table, rebuilt on each refresh
     v_dash_*  view, computed at query time
     sp_dash_* stored procedure

   Run section 0 first: it tells you what exists, what is missing, and whether any
   object is the wrong KIND (BigQuery refuses to let CREATE OR REPLACE switch a
   name between table and view, so a mismatch fails the next deployment).
   ============================================================================= */


/* =============================================================================
   0. HEALTH CHECK -- run this first
   ============================================================================= */

WITH expected AS (
  SELECT * FROM UNNEST([
    STRUCT('dash_nmv_factor' AS nm, 'BASE TABLE' AS ty, '01' AS src),
    ('dash_base_order_day','BASE TABLE','01'), ('dash_target_day','BASE TABLE','01'),
    ('dash_dq_platform_day','BASE TABLE','01'),
    ('dash_run_params','BASE TABLE','02'), ('dash_base_sku_day','BASE TABLE','02'),
    ('dash_page1_wow','BASE TABLE','02'), ('dash_page2_mtd','BASE TABLE','02'),
    ('dash_highlights','BASE TABLE','02'), ('dash_stock_lists','BASE TABLE','02'),
    ('dash_page_summary','BASE TABLE','02'),
    ('dash_store_hour_wow','BASE TABLE','03'), ('dash_action_context','BASE TABLE','03'),
    ('dash_action_items','BASE TABLE','03'), ('v_dash_trend_page1','VIEW','03'),
    ('v_dash_trend_page2','VIEW','03'), ('v_dash_stock_lists_bi','VIEW','03'),
    ('dash_trend_weekly','BASE TABLE','04'), ('dash_trend_monthly','BASE TABLE','04'),
    ('dash_materiality_config','BASE TABLE','04'), ('dash_material_points','BASE TABLE','04'),
    ('v_dash_ai_facts_core','VIEW','04'), ('v_dash_ai_facts','VIEW','04'),
    ('dash_ai_narrative','BASE TABLE','04'), ('v_dash_report','VIEW','04'),
    ('v_dash_ai_cost','VIEW','04'), ('v_dash_consistency_check','VIEW','04'),
    ('dash_ai_review','BASE TABLE','05'), ('dash_ai_feedback','BASE TABLE','05'),
    ('dash_ai_guidance','BASE TABLE','05'), ('v_dash_ai_quality','VIEW','05'),
    ('v_dash_report_reviewed','VIEW','05')
  ])
)
SELECT
   e.src AS from_script
  ,e.nm  AS object_name
  ,e.ty  AS should_be
  ,IFNULL(t.table_type,'** MISSING **') AS currently_is
  ,IFNULL(CAST(p.row_count AS STRING), IF(e.ty='VIEW','(view)','-')) AS rows_now
  ,CASE
     WHEN t.table_name IS NULL          THEN 'MISSING - run script ' || e.src
     WHEN t.table_type <> e.ty          THEN 'TYPE CONFLICT - run 00b_preflight_type_conflicts.sql'
     WHEN e.ty='BASE TABLE' AND IFNULL(p.row_count,0)=0 THEN 'empty - re-run script ' || e.src
     ELSE 'ok'
   END AS status
FROM expected e
LEFT JOIN `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.TABLES` t ON t.table_name = e.nm
LEFT JOIN `marine-cycle-484213-b4.reportdb.__TABLES__` p ON p.table_id = e.nm
ORDER BY e.src, e.nm;


/* =============================================================================
   1. FOUNDATION  (01_foundation.sql)
   The atomic layer. Everything else is derived from these four.
   ============================================================================= */

-- dash_nmv_factor
-- Measured NMV/GMV ratio per China platform, from orders older than 30 days so
-- cancellations have settled. Used to model NMV inside the recent 30-day window,
-- where observed net is still inflating.
-- WATCH: must return 4 rows. At 2, Xiaohongshu and Douyin are silently using the
-- 0.21 fallback instead of their own measured factors - re-run 01_foundation.sql.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_nmv_factor` ORDER BY level_3;

-- dash_base_order_day  (~70k rows)
-- THE core fact table. One row per order x day x channel. Exists because
-- fn_performance_snapshot_v2 has no usable bill count: its order_confirmed column
-- counts order LINES, overstating true bills by +34% to +2,900% depending on
-- channel. Carries both GMV and NMV so China movement can be read on a stable base.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
ORDER BY period_date DESC, nmv DESC LIMIT 200;

-- dash_target_day
-- The 2026 sales plan, one row per date x channel, with the flags that decide
-- whether attainment is meaningful: is_low_target (full-month target < 500m VND),
-- is_target_invalid (target <= 0, e.g. TL Pop-up December is -864m), and
-- is_unmapped_channel (Pop-ups carry plan but have no actuals channel).
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_target_day`
WHERE sale_date >= DATE_TRUNC(CURRENT_DATE('Asia/Ho_Chi_Minh'), MONTH)
ORDER BY sale_date, level_2;

-- dash_dq_platform_day
-- Per-platform freshness. Tmall and Taobao upload manually once a week, so they
-- are complete only to the most recent Sunday while everything else runs to T-1.
-- data_complete_through is what MTD attainment is pro-rated against, so each
-- channel is compared like-for-like.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_dq_platform_day`
ORDER BY is_weekly_load DESC, level_2, level_3;


/* =============================================================================
   2. PAGES  (02_pages.sql)
   ============================================================================= */

-- dash_run_params  (1 row)
-- Single source of truth for every date boundary and threshold. All downstream
-- objects read dates from here, so the two pages can never drift onto different
-- weeks. Change a threshold HERE, not in the individual scripts.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`;

-- dash_base_sku_day  (~47k rows)
-- SKU-grain units, read straight from the China raw tables so it is immune to the
-- 4.03x fan-out in the Taobao/Tmall TVF. Feeds the trending stock list only.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_base_sku_day`
ORDER BY period_date DESC, units_sold DESC LIMIT 200;

-- dash_page1_wow
-- Page 1 section 2. Current week vs prior week by channel x country, with the
-- diagnosis from the decision table. diagnosis_source says whether it is an exact
-- decision-table match or derived: the table covers 5 of 27 possible direction
-- combinations, and nothing is forced into a row it does not fit.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`
ORDER BY ABS(delta_nmv) DESC;

-- dash_page2_mtd
-- Page 2 section 2. MTD vs target, cut at each channel's own completeness date.
-- attainment_pct is NULL where suppressed; attainment_note always says why.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
ORDER BY ABS(gap_to_target) DESC;

-- dash_highlights
-- Section 1 for both pages. Max 3 highlights + 3 lowlights, ranked by ABSOLUTE
-- VND impact, never percentage - a -5% on the largest channel outranks a -40% on
-- a trivial one. Rows with suppressed attainment can never headline.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_highlights`
ORDER BY page, item_type, rank_in_group;

-- dash_stock_lists
-- Section 3. Four lists, top 10 each: OVERSTOCK, UNDERSTOCK, TRENDING and
-- DISCONTINUED. The fourth is an addition - fn_stats_product_v2 excludes
-- sale-ended SKUs from every score, yet they hold a large share of stock value.
-- NOTE: rank_value is VND for three lists but UNITS for TRENDING. Read rank_metric.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_stock_lists`
ORDER BY list_name, rank_in_list;

-- dash_page_summary  (2 rows)
-- The headline figures. headline_note carries the Pop-up exclusion in words -
-- never publish headline_pct without it.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_page_summary` ORDER BY page;


/* =============================================================================
   3. ACTIONS AND BILINGUAL LABELS  (03_actions_and_bilingual.sql)
   ============================================================================= */

-- dash_store_hour_wow
-- Trading-window attribution for offline stores. order_date carries real
-- time-of-day, so a store's move localises to a two-to-four hour window - which is
-- what turns "sales are down" into a directive someone can act on.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_store_hour_wow`
ORDER BY delta_nmv;

-- dash_action_context
-- The evidence behind each action: which level_3 drove the move, the worst trading
-- window, and the run-rate step-up needed to close an MTD gap. Inspect this when
-- an action looks wrong - the anchor will be visible here.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_action_context`
ORDER BY page, item_type, rank_in_group;

-- dash_action_items
-- Section 4. Owner-tagged directives, each naming a concrete target: a store plus
-- trading window, a platform, or a SKU code. Created ONLY here - 02_pages.sql no
-- longer creates a generic version that could overwrite this one.
-- NOTE: discount-depth directives are deliberately absent. Gross vs net differs by
-- 0-5.7% and that gap is platform fees, not item discount, so any "cut discount
-- from X to Y" instruction would be invented.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_action_items`
ORDER BY page, section, action_no;

-- v_dash_trend_page1 / v_dash_trend_page2 / v_dash_stock_lists_bi
-- PRESENTATION ONLY. These wrap the tables above and add Vietnamese label columns
-- (country_vi, driver_vi, diagnosis_vi, list_name_vi, ...). Nothing in the
-- pipeline reads them - the only consumer is the notebook. The Vietnamese here is
-- a deterministic SQL mapping, not model output, so it costs nothing and cannot
-- drift between runs. Point Looker Studio at THESE, not the raw tables.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_trend_page1` ORDER BY ABS(delta_nmv) DESC;
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_trend_page2` ORDER BY ABS(gap_to_target) DESC;
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_stock_lists_bi` ORDER BY list_name, rank_in_list;


/* =============================================================================
   4. TRENDS AND AI LAYER  (04_trends_and_ai.sql)
   ============================================================================= */

-- dash_trend_weekly
-- 8 complete weeks plus the current one, by channel and platform. The trailing
-- range columns deliberately EXCLUDE the current week, otherwise the current value
-- would sit inside its own comparison range and could never be flagged an outlier.
-- bills counts only orders with value: zero-value orders were inflating bills 7%
-- and deflating AOV by the same, which matters against a 15% threshold.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_trend_weekly`
ORDER BY country, level_2, week_start;

-- dash_trend_monthly
-- 6 months of attainment and pace. This is the view the WoW page structurally
-- cannot give you: a channel can post triple-digit weekly growth while sitting
-- far below plan every month of the year.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_trend_monthly`
WHERE NOT is_low_target AND NOT is_unmapped_channel
ORDER BY country, level_2, month_start;

-- dash_materiality_config  (1 row)
-- The filter thresholds, in one editable place. p_enable_abs_rule = R4, which
-- admits the top absolute movers regardless of percentage. Set it FALSE for
-- literal +/-15% compliance - but see dash_material_points first to check what
-- that would suppress.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_materiality_config`;

-- dash_material_points
-- THE consistency anchor. One SQL-computed set of points that exec_summary,
-- highlights, lowlights and actions all draw from, so a point cannot appear in one
-- field and vanish from another. r1..r4 show which rule admitted each point;
-- material_reason says it in words.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_material_points` ORDER BY point_id;

-- Points carried ONLY by R4: below the percentage thresholds but too large in VND
-- to hide. These are exactly what a literal reading of the rules would suppress.
SELECT point_id, country, level_2, ROUND(delta_nmv/1e6) AS delta_mVND, material_reason
FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
WHERE r4_absolute AND NOT (r1_pct OR r2_range OR r3_pace);

-- v_dash_ai_facts_core / v_dash_ai_facts
-- Prompt assembly. _core builds the fact block; the outer view prepends any
-- approved style guidance. Inspect the prompt here BEFORE paying to generate.
SELECT page, period_key, facts_hash, LENGTH(prompt) AS prompt_chars,
       ROUND(LENGTH(prompt)/4) AS approx_tokens
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` ORDER BY page;

-- Read the full prompt for one page:
SELECT prompt FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` WHERE page = 'PAGE1_WOW';

-- dash_ai_narrative  (2 rows, one per page)
-- The model output cache, keyed by (page, period_key). An unchanged re-run makes
-- ZERO model calls. facts_hash forces regeneration only when the facts restate.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_ai_narrative` ORDER BY page;

-- v_dash_report
-- What a dashboard binds to if you are not using the review layer. Falls back to
-- deterministic rule-generated prose if the model is unavailable; narrative_source
-- says which you are looking at (AI / AI_STALE / RULE).
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_report` ORDER BY page;

-- v_dash_ai_cost
-- Cost computed from the token counts actually stored, not an assumption.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_cost` ORDER BY generated_at DESC;

-- v_dash_consistency_check
-- Requirement "one narrative, four views", enforced. missing_from_exec_summary and
-- missing_from_highlights name any point covered in one field but not the other.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_consistency_check`;


/* =============================================================================
   5. REVIEW AND FEEDBACK  (05_review_and_feedback.sql)
   ============================================================================= */

-- dash_ai_review
-- The score card. det_* columns are DETERMINISTIC SQL checks and are
-- authoritative - unsupported_numbers lists any figure in the narrative that does
-- not appear in the facts, which is what stops a fabricated number reaching a
-- reader. judge_* columns come from an LLM and are ADVISORY ONLY: a model grading
-- a model shares its blind spots, so it has no authority over numeric accuracy.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_ai_review`
ORDER BY reviewed_at DESC LIMIT 20;

-- Failures only:
SELECT page, attempt_no, verdict, unsupported_numbers, missing_points,
       fabricated_points, judge_issue, reviewed_at
FROM `marine-cycle-484213-b4.reportdb.dash_ai_review`
WHERE NOT det_pass OR verdict <> 'PUBLISH'
ORDER BY reviewed_at DESC;

-- dash_ai_feedback
-- Human and judge feedback. feedback_text is UNTRUSTED and never enters a prompt.
-- Rows sit at PROPOSED until explicitly approved; screen_flag marks anything that
-- looks like an attempt to relax a hard rule.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
ORDER BY submitted_at DESC;

-- dash_ai_guidance
-- The only feedback that actually reaches the model. Capped at 10 active lines and
-- injected BEFORE the hard rules, so it can never override them.
SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_ai_guidance`
ORDER BY guidance_version DESC;

-- v_dash_ai_quality
-- Did guidance help? Scores grouped by guidance_version. If a version did not lift
-- the average, retire the line it added rather than stacking another on top.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_quality`
ORDER BY guidance_version, page;

-- v_dash_report_reviewed
-- ** BIND YOUR DASHBOARD TO THIS ONE. ** Same as v_dash_report but never publishes
-- a quarantined narrative: on failure it falls back to rule-generated text, and the
-- exec summary is NULLed rather than shown unverified.
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_dash_report_reviewed` ORDER BY page;


/* =============================================================================
   6. STORED PROCEDURES
   =============================================================================
   sp_dash_run_dashboard()      generate -> review -> retry once. THE DAILY CALL.
   sp_dash_generate_ai(force)   generate only; TRUE forces past the cache
   sp_dash_review_ai(attempt)   score only
   sp_dash_submit_feedback(...) record feedback as PROPOSED
   sp_dash_approve_guidance(id, reviewer, approve)  the human gate
   ============================================================================= */

-- Daily:
-- CALL `marine-cycle-484213-b4.reportdb.sp_dash_run_dashboard`();

-- Definitions and argument lists:
SELECT routine_name, ARRAY_TO_STRING(ARRAY(
         SELECT CONCAT(parameter_name,' ',data_type)
         FROM `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.PARAMETERS` p
         WHERE p.specific_name = r.routine_name
         ORDER BY ordinal_position), ', ') AS arguments
FROM `marine-cycle-484213-b4.reportdb.INFORMATION_SCHEMA.ROUTINES` r
WHERE routine_name LIKE 'sp_dash%'
ORDER BY routine_name;