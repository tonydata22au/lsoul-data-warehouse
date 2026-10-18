CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.reportdb.sp_ai_product_stock_insights`(
   i_type                  INT64    -- 0 = per SKU x warehouse, 1 = per SKU
  ,i_number_year_back      INT64
  ,i_days_range            INT64
  ,i_avg_units_sold_expect INT64
  ,i_FromDate              DATE
  ,i_ToDate                DATE
  ,i_model                 STRING   -- e.g. 'agent_platform_ai'
  ,i_max_skus              INT64    -- cost guard; NULL -> 200
)
OPTIONS (description = """Generates AI stock insights from fn_stats_product_v2 and upserts them
into reportdb.ai_product_stock_insights + ai_product_stock_exec_summary.

  CALL `marine-cycle-484213-b4.reportdb.sp_ai_product_stock_insights`(
       1, 0, 90, 9, NULL, NULL, 'marine-cycle-484213-b4.reportdb.gemini_model', 200);""")
/* -----------------------------------------------------------------------------
   3. USAGE
   --------------------------------------------------------------------------

   -- SKU-level (buying / markdown decisions)
   CALL `marine-cycle-484213-b4.reportdb.sp_ai_product_stock_insights`(
        1, 0, 90, 9, NULL, NULL, 'marine-cycle-484213-b4.reportdb.gemini_model', 9000);

   -- Warehouse-level (rebalancing / local clearance)
   CALL `marine-cycle-484213-b4.reportdb.sp_ai_product_stock_insights`(
        0, 0, 30, 9, NULL, NULL, 'marine-cycle-484213-b4.reportdb.gemini_model', 9000);

   -- Read the overstock action list
   SELECT report_date, variation_code, product_name, warehouse_name,
          sl_ton_kho, DOH,units_sold_day_range, excess_value, alert_code,
          ai_headline, ai_action_code, ai_actions, ai_expected_impact
   FROM `marine-cycle-484213-b4.reportdb.ai_product_stock_insights`
   WHERE report_type = 1
     AND report_date = (SELECT MAX(report_date) FROM `marine-cycle-484213-b4.reportdb.ai_product_stock_insights`)
     AND alert_code IN ('DEAD_STOCK','OVERSTOCK_CRITICAL','OVERSTOCK_HIGH')
     AND 
        (ai_headline IS NOT NULL
        OR ai_action_code IS NOT NULL
        OR ai_expected_impact IS NOT NULL
        )
   ORDER BY ai_priority, excess_value DESC;

   -- Executive briefing
   SELECT report_date, ai_summary, ai_top_risks, ai_top_actions, ai_outlook
   FROM `marine-cycle-484213-b4.reportdb.ai_product_stock_exec_summary`
   WHERE report_type = 1
   ORDER BY report_date DESC LIMIT 1;

   -- Schedule (BigQuery scheduled query, daily 06:00 ICT):
   --   CALL ...sp_ai_product_stock_insights(1, 0, 90, 9, NULL, NULL, '<model>', 200);
   --   CALL ...sp_ai_product_stock_insights(0, 0, 30, 9, NULL, NULL, '<model>', 300);
   -------------------------------------------------------------------------- */
BEGIN
  
  DECLARE v_run_id      STRING    DEFAULT GENERATE_UUID();
  DECLARE v_now         TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_scope       STRING    DEFAULT IF(i_type = 1, 'SKU', 'SKU_WAREHOUSE');
  DECLARE v_max_skus    INT64     DEFAULT IFNULL(i_max_skus, 200);
  DECLARE v_report_date DATE;
  DECLARE v_candidates  INT64;
  DECLARE v_sql         STRING;

  IF i_type NOT IN (0, 1) THEN
    RAISE USING MESSAGE = 'i_type must be 0 (SKU x warehouse) or 1 (SKU snapshot).';
  END IF;

  ---------------------------------------------------------------------------
  -- 2.1 Snapshot. Only the latest row per grain: insights are about the
  --     position we are in now, not about every historical day.
  ---------------------------------------------------------------------------
  CREATE OR REPLACE TEMP TABLE t_snapshot AS
  SELECT
     period_date
    ,variation_code
    ,IFNULL(warehouse_id, '')   AS warehouse_id
    ,IFNULL(warehouse_name, '') AS warehouse_name
    ,product_code
    ,product_name
    ,variation_attributes
    ,product_days_since_launch
    ,days_range
    ,is_inactive
    ,retail_price
    ,sl_ton_kho
    ,sl_ton_kho_diff
    ,tong_gia_tri_hang_ton_kho_theo_gia_ban
    ,ton_kho_running_days
    ,emty_stock_days
    ,units_sold_day_range
    ,sale_velocity
    ,expected_velocity
    ,sell_through_rate
    ,DOH
    ,doh_is_infinite
    ,colour_bucket
    ,health_score
    ,alert_code
    ,alert_severity
    ,overstock_risk_score
    ,excess_units
    ,excess_value
    ,suggested_discount_pct
    ,sale_channel
    ,order_sources_name
  FROM `marine-cycle-484213-b4.reportdb.fn_stats_product_v2`(
         i_type, i_number_year_back, i_days_range, i_avg_units_sold_expect, i_FromDate, i_ToDate)
  --WHERE is_latest = 1
  ;

  SET v_report_date = (SELECT MAX(period_date) FROM t_snapshot);

  -- report_date is the partition key on both target tables, so a NULL snapshot
  -- must stop here rather than fail inside the MERGE.
  IF v_report_date IS NULL THEN
    SELECT v_run_id AS run_id,
           'No rows returned for these parameters - nothing generated.' AS status;
    RETURN;
  END IF;

  ---------------------------------------------------------------------------
  -- 2.2 Portfolio KPIs. Computed in SQL and handed to the model as facts, so
  --     the executive summary can never invent a total.
  ---------------------------------------------------------------------------
  CREATE OR REPLACE TEMP TABLE t_kpi AS
  SELECT
     COUNT(*)                                                        AS sku_rows
    ,COUNT(DISTINCT variation_code)                                  AS sku_count
    ,SUM(sl_ton_kho)                                                 AS total_units_on_hand
    ,ROUND(SUM(tong_gia_tri_hang_ton_kho_theo_gia_ban), 0)           AS total_stock_value
    ,SUM(units_sold_day_range)                                       AS units_sold_in_window
    ,ROUND(AVG(NULLIF(DOH, 0)), 1)                                   AS avg_doh
    ,ROUND(AVG(sell_through_rate), 4)                                AS avg_sell_through
    ,COUNTIF(colour_bucket = '1-GREEN')                              AS n_green
    ,COUNTIF(colour_bucket = '2-YELLOW')                             AS n_yellow
    ,COUNTIF(colour_bucket = '3-RED')                                AS n_red
    ,COUNTIF(colour_bucket = '4-BLACK')                              AS n_black
    ,COUNTIF(alert_code IN ('DEAD_STOCK','OVERSTOCK_CRITICAL'))      AS n_overstock_critical
    ,COUNTIF(alert_code = 'OVERSTOCK_HIGH')                          AS n_overstock_high
    ,COUNTIF(alert_code IN ('STOCKOUT_NOW','STOCKOUT_IMMINENT'))     AS n_stockout_urgent
    ,ROUND(SUM(excess_value), 0)                                     AS total_excess_value
    ,SUM(excess_units)                                               AS total_excess_units
    ,ROUND(SAFE_DIVIDE(SUM(excess_value),
             NULLIF(SUM(tong_gia_tri_hang_ton_kho_theo_gia_ban), 0)), 4) AS excess_value_share
  FROM t_snapshot
  WHERE is_inactive = 0;

  ---------------------------------------------------------------------------
  -- 2.3 Candidates. Only SKUs that need a human decision go to the model, and
  --     only the top v_max_skus of those, ranked by capital at risk. This is
  --     the single biggest cost lever in the whole procedure.
  ---------------------------------------------------------------------------
  CREATE OR REPLACE TEMP TABLE t_candidates AS
  WITH ranked AS (
    SELECT
       s.*
      ,CONCAT(CAST(i_type AS STRING), '|', s.variation_code, '|', s.warehouse_id) AS row_key
      ,ROW_NUMBER() OVER (
         ORDER BY s.alert_severity ASC,
                  s.excess_value DESC,
                  s.overstock_risk_score DESC
       ) AS rn
    FROM t_snapshot s
    WHERE s.alert_code <> 'HEALTHY'
      AND NOT (s.is_inactive = 1 AND s.sl_ton_kho = 0)   -- discontinued and empty: nothing to decide
  )
  SELECT
     r.* EXCEPT (rn)
    ,CONCAT(
      -- ---------- role, varies by report type ----------
      CASE WHEN i_type = 1 THEN """You are LSOUL's senior merchandise planner. You are reviewing a SKU-LEVEL stock
forecasting report: stock is aggregated across ALL warehouses, so your decisions are
buying, pricing and lifecycle decisions for the SKU as a whole (reorder, markdown,
bundle, clearance, discontinue). Do NOT recommend inter-warehouse transfers — this
report cannot see individual warehouses."""
           ELSE """You are LSOUL's inventory operations planner. You are reviewing a WAREHOUSE-LEVEL
stock forecasting report: one row = one SKU in one warehouse (Vietnam / China / Thailand).
Your decisions are local — rebalancing stock between warehouses, pushing the channel
that serves this warehouse, and location-specific clearance. If cover is long in this
warehouse, always consider a transfer to a location where the same SKU is selling
before recommending a markdown."""
      END

      -- ---------- shared framing ----------
      ,"""

BUSINESS CONTEXT
- LSOUL sells fashion. Overstock is the primary risk: it locks up cash and ages badly.
- Thresholds already applied upstream: DOH <= 90d healthy, <= 180d watch,
  < 360d severe, >= 360d dead stock. Velocity is judged against expected_velocity.
- `suggested_discount_pct` is a rule-based STARTING POINT. You may raise it if the
  evidence is worse than the rule assumes, or lower it if the SKU is young or newly
  restocked. Always say why you deviated.
- A SKU launched under 56 days ago has not had a fair chance; prefer marketing and
  visibility actions over markdown for those.

YOUR TASK
Read the SKU record below and return:
- headline    : one line, max 120 characters, stating the verdict.
- diagnosis   : 2-3 sentences explaining WHY this SKU is in this state. Cite the
                actual numbers (DOH, velocity, sell-through, excess units).
- actions     : 2 to 4 concrete steps. Each must be executable this week and must
                name a number (a discount %, a target unit count, a channel, a
                reorder quantity, a deadline). No generic advice such as
                "monitor further" or "improve marketing".
- action_code : exactly one of REPLENISH_URGENT, REPLENISH, HOLD, MARKDOWN, BUNDLE,
                CLEARANCE, TRANSFER_STOCK, DISCONTINUE.
- expected_impact : one sentence quantifying the expected result, e.g. "frees up
                ~120 units and ~18 million VND of tied-up capital within 6 weeks".
- priority    : 1 (act this week) to 5 (informational). Weight capital at risk
                (excess_value) above unit count.
- confidence  : 0.0 to 1.0. Lower it when the sales window is thin
                (units_sold_day_range < 5) or the SKU is very young.

OUTPUT LANGUAGE
Give the text in Vietnamese. Every free-text field - headline, diagnosis, actions
and expected_impact - must be written in Vietnamese, using natural Vietnamese
retail/merchandising vocabulary. Keep action_code in English exactly as listed
above; priority and confidence are numbers.

RULES
- Use ONLY the numbers given below. Never estimate a figure that is not present.
- If units_sold_day_range = 0 and stock > 0, this is dead stock: do not propose
  demand-generation as the only lever — include a liquidation path.
- Be specific and commercial, not encouraging. This feeds a decision, not a report.

SKU RECORD (JSON):
"""
      -- ---------- the data ----------
      ,TO_JSON_STRING(STRUCT(
          r.variation_code            AS sku
         ,r.product_name              AS product_name
         ,r.variation_attributes      AS variant
         ,r.warehouse_name            AS warehouse
         ,r.retail_price              AS retail_price_vnd
         ,r.product_days_since_launch AS days_since_launch
         ,r.days_range                AS window_days
         ,r.sl_ton_kho                AS stock_on_hand
         --,r.sl_ton_kho_diff           AS stock_change_vs_prev
         ,r.tong_gia_tri_hang_ton_kho_theo_gia_ban AS stock_value_vnd
         ,r.units_sold_day_range      AS units_sold_in_window
         ,r.sale_velocity             AS velocity_units_per_day
         ,r.expected_velocity         AS expected_velocity_units_per_day
         ,r.sell_through_rate         AS sell_through_rate
         ,r.DOH                       AS days_of_inventory_on_hand
         ,r.doh_is_infinite           AS never_sold_flag
         ,r.ton_kho_running_days      AS days_holding_stock
         ,r.emty_stock_days           AS consecutive_days_out_of_stock
         ,r.colour_bucket             AS colour_bucket
         ,r.health_score              AS health_score_0_12
         ,r.alert_code                AS alert_code
         ,r.alert_severity            AS alert_severity_1_best_4
         ,r.overstock_risk_score      AS overstock_risk_score_0_100
         ,r.excess_units              AS excess_units_vs_90d_target
         ,r.excess_value              AS excess_value_vnd
         ,r.suggested_discount_pct    AS rule_based_discount_pct
         ,r.sale_channel              AS sale_channel
         ,r.order_sources_name        AS order_source
      ))
     ) AS prompt
  FROM ranked r
  WHERE r.rn <= v_max_skus;

  SET v_candidates = (SELECT COUNT(*) FROM t_candidates);

  ---------------------------------------------------------------------------
  -- 2.4 Per-SKU generation.
  --     EXECUTE IMMEDIATE is required only because MODEL takes a literal path.
  --     The prompts themselves were built statically above.
  ---------------------------------------------------------------------------
  IF v_candidates > 0 THEN

    SET v_sql = FORMAT("""
      CREATE OR REPLACE TEMP TABLE t_ai AS
      SELECT
         row_key
        ,headline
        ,diagnosis
        ,actions
        ,action_code
        ,expected_impact
        ,priority
        ,confidence
      FROM AI.GENERATE_TABLE(
        MODEL `%s`,
        (SELECT row_key, prompt FROM t_candidates),
        STRUCT(
          'headline STRING, diagnosis STRING, actions ARRAY<STRING>, action_code STRING, expected_impact STRING, priority INT64, confidence FLOAT64' AS output_schema,
          0.2  AS temperature,
          2048 AS max_output_tokens
        )
      )
    """, i_model);

    EXECUTE IMMEDIATE v_sql;

    /* ----------------------------------------------------------------------
       ML.GENERATE_TEXT alternative (older models / no structured output).
       Swap the block above for this, then parse with JSON_VALUE:

         CREATE TEMP TABLE t_ai_raw AS
         SELECT row_key, ml_generate_text_llm_result AS raw
         FROM ML.GENERATE_TEXT(
           MODEL `<model>`,
           (SELECT row_key,
                   CONCAT(prompt, '\\n\\nReturn ONLY valid JSON with keys: ',
                          'headline, diagnosis, actions (array of strings), ',
                          'action_code, expected_impact, priority, confidence.') AS prompt
            FROM t_candidates),
           STRUCT(0.2 AS temperature, 2048 AS max_output_tokens, TRUE AS flatten_json_output)
         );

         CREATE TEMP TABLE t_ai AS
         SELECT
            row_key
           ,JSON_VALUE(j, '$.headline')        AS headline
           ,JSON_VALUE(j, '$.diagnosis')       AS diagnosis
           ,ARRAY(SELECT JSON_VALUE(a) FROM UNNEST(JSON_QUERY_ARRAY(j, '$.actions')) a) AS actions
           ,JSON_VALUE(j, '$.action_code')     AS action_code
           ,JSON_VALUE(j, '$.expected_impact') AS expected_impact
           ,SAFE_CAST(JSON_VALUE(j, '$.priority')   AS INT64)   AS priority
           ,SAFE_CAST(JSON_VALUE(j, '$.confidence') AS FLOAT64) AS confidence
         FROM (
           SELECT row_key, SAFE.PARSE_JSON(REGEXP_REPLACE(raw, r'^```json\\s*|\\s*```$', '')) AS j
           FROM t_ai_raw
         );
       ------------------------------------------------------------------- */

    ---------------------------------------------------------------------------
    -- 2.5 Upsert. Re-running for the same report_date / grain overwrites rather
    --     than appending, so the report never shows two versions of one SKU.
    ---------------------------------------------------------------------------
    MERGE `marine-cycle-484213-b4.reportdb.ai_product_stock_insights` T
    USING (
      SELECT
         v_run_id     AS run_id
        ,v_now        AS generated_at
        ,i_type       AS report_type
        ,v_scope      AS report_scope
        ,c.period_date AS report_date
        ,i_days_range AS days_range
        ,c.variation_code
        ,c.warehouse_id
        ,c.warehouse_name
        ,c.product_code
        ,c.product_name
        ,c.variation_attributes
        ,c.sl_ton_kho
        ,c.units_sold_day_range
        ,c.sale_velocity
        ,c.sell_through_rate
        ,c.DOH
        ,c.colour_bucket
        ,c.alert_code
        ,c.alert_severity
        ,c.overstock_risk_score
        ,c.excess_units
        ,c.excess_value
        ,c.suggested_discount_pct
        ,a.headline        AS ai_headline
        ,a.diagnosis       AS ai_diagnosis
        ,a.actions         AS ai_actions
        ,a.action_code     AS ai_action_code
        ,a.expected_impact AS ai_expected_impact
        ,a.priority        AS ai_priority
        ,a.confidence      AS ai_confidence
      FROM t_candidates c
      JOIN t_ai a USING (row_key)
    ) S
    ON  T.report_type    = S.report_type
    AND T.report_date    = S.report_date
    AND T.variation_code = S.variation_code
    AND IFNULL(T.warehouse_id, '') = IFNULL(S.warehouse_id, '')
    WHEN MATCHED THEN UPDATE SET
       run_id = S.run_id, generated_at = S.generated_at, report_scope = S.report_scope
      ,days_range = S.days_range, warehouse_name = S.warehouse_name
      ,product_code = S.product_code, product_name = S.product_name
      ,variation_attributes = S.variation_attributes
      ,sl_ton_kho = S.sl_ton_kho, units_sold_day_range = S.units_sold_day_range
      ,sale_velocity = S.sale_velocity, sell_through_rate = S.sell_through_rate
      ,DOH = S.DOH, colour_bucket = S.colour_bucket
      ,alert_code = S.alert_code, alert_severity = S.alert_severity
      ,overstock_risk_score = S.overstock_risk_score
      ,excess_units = S.excess_units, excess_value = S.excess_value
      ,suggested_discount_pct = S.suggested_discount_pct
      ,ai_headline = S.ai_headline, ai_diagnosis = S.ai_diagnosis
      ,ai_actions = S.ai_actions, ai_action_code = S.ai_action_code
      ,ai_expected_impact = S.ai_expected_impact
      ,ai_priority = S.ai_priority, ai_confidence = S.ai_confidence
    WHEN NOT MATCHED THEN INSERT ROW;

  END IF;

  ---------------------------------------------------------------------------
  -- 2.6 Executive summary. One call, over KPIs the SQL already computed plus
  --     the ten largest exposures.
  ---------------------------------------------------------------------------
  CREATE OR REPLACE TEMP TABLE t_exec_input AS
  SELECT
    CONCAT(
      CASE WHEN i_type = 1 THEN """You are briefing LSOUL's leadership on the SKU-LEVEL stock forecasting report
(stock aggregated across all warehouses). Frame everything as buying, pricing and
lifecycle decisions."""
           ELSE """You are briefing LSOUL's leadership on the WAREHOUSE-LEVEL stock forecasting report
(one row per SKU per warehouse). Frame everything as fulfilment, rebalancing and
local clearance decisions."""
      END
     ,"""

Write an executive briefing for a reader who has 60 seconds.

- summary   : 1-2 sentences. Lead with the size of the overstock exposure in VND and
              what share of total stock value it represents. State whether the
              portfolio is healthier or at risk overall, and why.
- top_risks : 1-2 bullets, each naming a specific SKU or group and the VND amount
              at stake.
- top_actions : 1-2 bullets, each a decision leadership should approve this week,
              with a number attached (budget, discount %, unit target).
- outlook   : 1 sentences on what happens over the next 30-60 days if nothing changes.

OUTPUT LANGUAGE
Give the text in Vietnamese. All four fields - summary, top_risks, top_actions and
outlook - must be written in Vietnamese, using natural Vietnamese retail vocabulary.
SKU codes, product names and numbers stay exactly as supplied.

Use ONLY the figures supplied. Do not invent totals. Currency is VND.

PORTFOLIO KPIs (JSON):
"""
     ,(SELECT TO_JSON_STRING(k) FROM t_kpi k)
     ,"""

LARGEST EXPOSURES (JSON array):
"""
     ,(SELECT TO_JSON_STRING(ARRAY_AGG(
          STRUCT(variation_code AS sku, product_name, warehouse_name AS warehouse,
                 sl_ton_kho AS stock, days_range AS window_days, units_sold_day_range AS units_sold_in_window, DOH, sale_velocity, alert_code,
                 excess_units, excess_value, suggested_discount_pct)
          ORDER BY excess_value DESC LIMIT 10))
       FROM t_snapshot WHERE is_inactive = 0)
    ) AS prompt;

  SET v_sql = FORMAT("""
    CREATE OR REPLACE TEMP TABLE t_exec AS
    SELECT summary, top_risks, top_actions, outlook
    FROM AI.GENERATE_TABLE(
      MODEL `%s`,
      (SELECT prompt FROM t_exec_input),
      STRUCT(
        'summary STRING, top_risks ARRAY<STRING>, top_actions ARRAY<STRING>, outlook STRING' AS output_schema,
        0.3  AS temperature,
        2048 AS max_output_tokens
      )
    )
  """, i_model);

  EXECUTE IMMEDIATE v_sql;

  MERGE `marine-cycle-484213-b4.reportdb.ai_product_stock_exec_summary` T
  USING (
    SELECT
       v_run_id AS run_id
      ,v_now    AS generated_at
      ,i_type   AS report_type
      ,v_report_date AS report_date
      ,i_days_range  AS days_range
      ,(SELECT TO_JSON_STRING(k) FROM t_kpi k) AS kpi_json
      ,e.summary     AS ai_summary
      ,e.top_risks   AS ai_top_risks
      ,e.top_actions AS ai_top_actions
      ,e.outlook     AS ai_outlook
    FROM t_exec e
  ) S
  ON T.report_type = S.report_type AND T.report_date = S.report_date
  WHEN MATCHED THEN UPDATE SET
     run_id = S.run_id, generated_at = S.generated_at, days_range = S.days_range
    ,kpi_json = S.kpi_json, ai_summary = S.ai_summary
    ,ai_top_risks = S.ai_top_risks, ai_top_actions = S.ai_top_actions
    ,ai_outlook = S.ai_outlook
  WHEN NOT MATCHED THEN INSERT ROW;

  SELECT
     v_run_id      AS run_id
    ,i_type        AS report_type
    ,v_scope       AS report_scope
    ,v_report_date AS report_date
    ,v_candidates  AS skus_sent_to_model;

END;