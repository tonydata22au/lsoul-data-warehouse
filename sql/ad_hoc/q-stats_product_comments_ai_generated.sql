
/*
Author : Toan Pham
Date   : 2026-08-09

WHY THE MODEL IS NOT CALLED HERE
  A TVF body is re-executed on every query. Calling AI.GENERATE in the SELECT list
  would fire one Vertex AI request per row, per refresh:

     i_type = 0, 5,000 SKUs x 3 warehouses x 90 days  ~= 1.35M rows
     -> 1.35M model calls, every time someone opens the dashboard

  versus the cached path, which generates only the SKUs that carry an open decision
  (non-HEALTHY alert, capped by i_max_skus) once per day - typically 100-300 calls.

  Cost is only the first problem. A live call in the TVF also means:
    - latency measured in minutes, inside an interactive report;
    - a different sentence on every refresh, so nobody can reconcile today's report
      against the copy they read yesterday;
    - Vertex AI requests-per-minute quota becoming the report's bottleneck, with
      partial failures surfacing as NULL comments mid-result and no way to retry
      from inside a table function.

  So: risk rules in SQL, narrative generated once in the procedure, joined here.

  A live variant is shown at the bottom of this file for ad-hoc use.

TESTING
  SELECT variation_code, product_name, DOH, alert_code, comments, comments_source
  FROM `marine-cycle-484213-b4.reportdb.fn_stats_product_comments_ai_generated`(1,0,90,9,NULL,NULL)
  WHERE alert_severity <= 2
  ORDER BY excess_value DESC;
*/

SELECT
   s.* EXCEPT (comments)

  -- Both versions stay visible, so a reader can always see what the rule said.
  ,s.comments        AS comments_rule
  ,a.ai_headline     AS comments_ai

  -- The column your report binds to.
  ,COALESCE(a.ai_headline, s.comments) AS comments
  ,CASE
     WHEN a.ai_headline IS NULL THEN 'RULE'
     WHEN DATE_DIFF(CURRENT_DATE(), DATE(a.generated_at), DAY) > 7 THEN 'AI_STALE'
     ELSE 'AI'
   END AS comments_source

  -- The rest of the generated payload, for drill-down.
  ,a.ai_diagnosis
  ,a.ai_actions
  ,a.ai_action_code
  ,a.ai_expected_impact
  ,a.ai_priority
  ,a.ai_confidence
  ,a.generated_at AS ai_generated_at
  ,DATE_DIFF(CURRENT_DATE(), DATE(a.generated_at), DAY) AS ai_age_days
FROM `marine-cycle-484213-b4.reportdb.report_order_product_inventory_summary` s
LEFT JOIN `marine-cycle-484213-b4.reportdb.ai_product_stock_insights` a
       ON a.report_type    = 1
      AND a.variation_code = s.variation_code
      AND IFNULL(a.warehouse_id, '') = IFNULL(s.warehouse_id, '')


/* =============================================================================
   LIVE VARIANT - ad-hoc only, never for a dashboard
   =============================================================================
   AI.GENERATE is a SCALAR function, so it can sit directly in a SELECT list.
   (ML.GENERATE_TEXT cannot: it is table-valued - it consumes a table and returns
   a table - so using it would mean restructuring the whole function around it.)

   Note the three guards. Without all of them this is a runaway cost:
     1. is_latest = 1        - one row per SKU, not one per SKU per day
     2. alert_code <> 'HEALTHY' - only SKUs with an open decision
     3. LIMIT                - a hard ceiling regardless of what the filters return

   Run it as a query, not as a saved TVF, so nobody can point a BI tool at it.
   ---------------------------------------------------------------------------
   
   SELECT
      variation_code
     ,product_name
     ,sl_ton_kho
     ,DOH
     ,sale_velocity
     ,alert_code
     ,excess_value
     ,AI.GENERATE(
        CONCAT(
          'You are merchandise planner of LSOUL. Write ONE sentence (max 120 ',
          'characters) giving the verdict on this SKU and the action to take now. ',
          'Use ONLY the figures supplied; never estimate a number that is not present. ',
          'Give the text in Vietnamese. Data: ',
          TO_JSON_STRING(STRUCT(
             variation_code AS sku
            ,product_name
            ,sl_ton_kho              AS stock_on_hand
            ,units_sold_day_range    AS units_sold_in_window
            ,sale_velocity           AS velocity_per_day
            ,expected_velocity       AS expected_velocity
            ,sell_through_rate
            ,DOH                     AS days_of_cover
            ,colour_bucket
            ,alert_code
            ,excess_units
            ,excess_value
            ,suggested_discount_pct
          ))
        )
       --,connection_id => 'us.<YOUR_CONNECTION_ID>'
       ,endpoint      => 'gemini-3.5-flash'
      ).result AS comments_ai_live
   FROM `marine-cycle-484213-b4.reportdb.fn_stats_product_v2`(1,0,90,9,NULL,NULL)
   WHERE is_latest = 1
     AND alert_code <> 'HEALTHY'
   ORDER BY excess_value DESC
   LIMIT 50;
========================================================================== */
