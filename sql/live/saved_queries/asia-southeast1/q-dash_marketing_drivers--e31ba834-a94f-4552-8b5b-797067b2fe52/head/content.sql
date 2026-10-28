/* =============================================================================
   dash_marketing_drivers   -- NEW 2026-09-06
   -----------------------------------------------------------------------------
   Answers one question, additively: sales for this week/month moved by X% versus
   the comparable prior period - how much of that is explained by marketing, and
   by which lever?

   GRAIN: one row per (period_type, period_start_date, country, level_2, level_3,
   driver_name). period_type is 'WTD' or 'MTD'.

   WHY THIS IS A NEW TABLE AND NOT A REWRITE OF dash_action_context
   ----------------------------------------------------------------
   The brief specified this grain FOR dash_action_context. That table is one row
   per highlight/lowlight, keyed (page, item_type, country, level_1, level_2), and
   dash_action_items and v_dash_ai_facts_core both read it that way, column by
   column. Re-keying it would break the whole action and AI layer, which the same
   brief forbids. The decomposition therefore lands here, and dash_action_context
   joins to it.

   -------------------------------------------------------------------------
   REVENUE BASIS: LSOUL NMV. Read this before quoting any number below.
   -------------------------------------------------------------------------
   `revenue` here is dash_base_order_day NMV for the channel - LSOUL's own,
   netted, cut-off order data. It is NOT ad-attributed. The decomposition
   therefore answers "how did channel revenue move relative to spend and
   efficiency", never "the spend caused this".

   That is a deliberate choice, because platform attribution cannot answer it:

   | source                        | covers          |
   |-------------------------------|-----------------|
   | TikTok Shop platform_orders   | 64% of spend    |
   | Google Ads conversions        | 0.7% of spend   |
   | Meta, TikTok auction: nothing | 36% of spend    |

   Meta reports no conversions and no revenue at all, so a platform-attributed
   decomposition would be NULL for a third of spend including VN Online. The
   platform figures ride along in platform_* and conversion_* columns for
   reconciliation. NEVER add the two families together, and never add either to
   revenue_cur.

   -------------------------------------------------------------------------
   SAME-PERIOD WINDOWS. A partial period is never compared to a full one.
   -------------------------------------------------------------------------
   elapsed_days = DATE_DIFF(report_date, period_start, DAY) + 1, and the prior
   period is restricted to its first elapsed_days days.

     WTD  2026-08-31..2026-09-03  vs  2026-08-24..2026-08-27   (4 days each)
     MTD  2026-09-01..2026-09-03  vs  2026-08-01..2026-08-03   (3 days each)

   The MTD prior end is clamped with LAST_DAY, so day 31 against a 30-day prior
   month truncates instead of overflowing into the next month.

   YTD is NOT built here: dash_base_ads_day only holds a 9-week window. A YTD
   decomposition must read fn_ads_media_daily(0) directly.
   ========================================================================== */

WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

/* the two period definitions, current and prior, both day-capped */
periods AS (
  SELECT 'WTD' AS period_type
        ,DATE_TRUNC(p.report_date, WEEK(MONDAY))                           AS cur_start
        ,p.report_date                                                     AS cur_end
        ,DATE_SUB(DATE_TRUNC(p.report_date, WEEK(MONDAY)), INTERVAL 7 DAY) AS prv_start
        ,DATE_SUB(p.report_date, INTERVAL 7 DAY)                           AS prv_end
        ,DATE_DIFF(p.report_date, DATE_TRUNC(p.report_date, WEEK(MONDAY)), DAY) + 1 AS elapsed_days
  FROM p
  UNION ALL
  SELECT 'MTD'
        ,p.month_start
        ,p.report_date
        ,DATE_SUB(p.month_start, INTERVAL 1 MONTH)
        ,LEAST(
           DATE_ADD(DATE_SUB(p.month_start, INTERVAL 1 MONTH), INTERVAL p.mtd_days_elapsed - 1 DAY),
           LAST_DAY(DATE_SUB(p.month_start, INTERVAL 1 MONTH)))
        ,p.mtd_days_elapsed
  FROM p
),

/* media, sale campaigns only, both sides of each period */
ads AS (
  SELECT
     pe.period_type, pe.cur_start, pe.cur_end, pe.prv_start, pe.prv_end, pe.elapsed_days
    ,b.country, b.level_2, b.level_3
    ,ANY_VALUE(b.level_1)                                                   AS level_1
    ,STRING_AGG(DISTINCT b.ads_channel, '+' ORDER BY b.ads_channel)         AS ads_channels
    ,STRING_AGG(DISTINCT b.buying_type, '+' ORDER BY b.buying_type)         AS buying_types
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.spend, 0))  AS spend_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.spend, 0))  AS spend_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end AND b.buying_type='Auction', b.spend, 0)) AS spend_auction_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end AND b.buying_type='Auction', b.spend, 0)) AS spend_auction_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end AND b.buying_type='GMV Max', b.spend, 0)) AS spend_gmvmax_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end AND b.buying_type='GMV Max', b.spend, 0)) AS spend_gmvmax_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.clicks, 0)) AS clicks_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.clicks, 0)) AS clicks_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.impressions, 0)) AS impressions_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.impressions, 0)) AS impressions_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.platform_orders, 0)) AS platform_orders_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.platform_orders, 0)) AS platform_orders_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.platform_gross_revenue_vnd, 0)) AS platform_revenue_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.platform_gross_revenue_vnd, 0)) AS platform_revenue_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.conversions, 0)) AS conversions_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.conversions, 0)) AS conversions_prv
    ,SUM(IF(b.period_date BETWEEN pe.cur_start AND pe.cur_end, b.conversion_value_vnd, 0)) AS conversion_value_cur
    ,SUM(IF(b.period_date BETWEEN pe.prv_start AND pe.prv_end, b.conversion_value_vnd, 0)) AS conversion_value_prv
  FROM `marine-cycle-484213-b4.reportdb.dash_base_ads_day` b
  CROSS JOIN periods pe
  WHERE b.is_sale_campaign
    AND b.period_date BETWEEN LEAST(pe.prv_start, pe.cur_start) AND GREATEST(pe.prv_end, pe.cur_end)
  GROUP BY 1,2,3,4,5,6,7,8,9
),

/* trade, the revenue basis */
sales AS (
  SELECT
     pe.period_type, o.country, o.level_2, o.level_3
    ,SUM(IF(o.period_date BETWEEN pe.cur_start AND pe.cur_end, o.nmv, 0))   AS revenue_cur
    ,SUM(IF(o.period_date BETWEEN pe.prv_start AND pe.prv_end, o.nmv, 0))   AS revenue_prv
    ,COUNT(DISTINCT IF(o.period_date BETWEEN pe.cur_start AND pe.cur_end, o.order_id, NULL)) AS bills_cur
    ,COUNT(DISTINCT IF(o.period_date BETWEEN pe.prv_start AND pe.prv_end, o.order_id, NULL)) AS bills_prv
    ,SUM(IF(o.period_date BETWEEN pe.cur_start AND pe.cur_end, o.units_sold, 0)) AS units_cur
    ,SUM(IF(o.period_date BETWEEN pe.prv_start AND pe.prv_end, o.units_sold, 0)) AS units_prv
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` o
  CROSS JOIN periods pe
  WHERE o.period_date BETWEEN LEAST(pe.prv_start, pe.cur_start) AND GREATEST(pe.prv_end, pe.cur_end)
  GROUP BY 1,2,3,4
),

/* new vs returning, derived from LSOUL's own customer_id.

   There is no new_customer_orders field in any ad feed, so CAC here is a
   BLENDED cost per newly-acquired customer in the channel, not an attributed
   one. A customer is "new" on the first date they ever appear in
   dash_base_order_day; the table holds only a 9-week window, so anyone whose
   true first order predates the window is misread as new. first_seen_in_window
   flags that - treat CAC as directional until a full-history customer dimension
   exists. Store TXmall carries almost no customer_id at all (0.1%) and is
   excluded from the count rather than silently understated. */
first_order AS (
  SELECT NULLIF(customer_id,'') AS customer_id, MIN(period_date) AS first_dt
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  WHERE NULLIF(customer_id,'') IS NOT NULL
  GROUP BY 1
),
new_cust AS (
  SELECT
     pe.period_type, o.country, o.level_2, o.level_3
    ,COUNT(DISTINCT IF(o.period_date BETWEEN pe.cur_start AND pe.cur_end
                       AND f.first_dt = o.period_date, f.customer_id, NULL)) AS new_customers_cur
    ,COUNT(DISTINCT IF(o.period_date BETWEEN pe.prv_start AND pe.prv_end
                       AND f.first_dt = o.period_date, f.customer_id, NULL)) AS new_customers_prv
    ,MIN(f.first_dt)                                                          AS earliest_first_dt
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` o
  JOIN first_order f ON f.customer_id = NULLIF(o.customer_id,'')
  CROSS JOIN periods pe
  WHERE o.period_date BETWEEN LEAST(pe.prv_start, pe.cur_start) AND GREATEST(pe.prv_end, pe.cur_end)
  GROUP BY 1,2,3,4
),

/* one row per channel-period, with every component both sides */
base AS (
  SELECT
     a.period_type
    ,a.cur_start AS period_start_date, a.cur_end AS period_end_date
    ,a.prv_start AS prv_start_date,    a.prv_end AS prv_end_date
    ,a.elapsed_days
    ,a.country, a.level_1, a.level_2, a.level_3
    ,a.ads_channels, a.buying_types
    ,a.spend_cur, a.spend_prv
    ,a.spend_auction_cur, a.spend_auction_prv
    ,a.spend_gmvmax_cur, a.spend_gmvmax_prv
    ,a.clicks_cur, a.clicks_prv
    ,a.impressions_cur, a.impressions_prv
    ,a.platform_orders_cur, a.platform_orders_prv
    ,a.platform_revenue_cur, a.platform_revenue_prv
    ,a.conversions_cur, a.conversions_prv
    ,a.conversion_value_cur, a.conversion_value_prv
    ,IFNULL(s.revenue_cur, 0) AS revenue_cur
    ,IFNULL(s.revenue_prv, 0) AS revenue_prv
    ,IFNULL(s.bills_cur, 0)   AS bills_cur
    ,IFNULL(s.bills_prv, 0)   AS bills_prv
    ,IFNULL(s.units_cur, 0)   AS units_cur
    ,IFNULL(s.units_prv, 0)   AS units_prv
    ,IFNULL(n.new_customers_cur, 0) AS new_customers_cur
    ,IFNULL(n.new_customers_prv, 0) AS new_customers_prv
    ,n.earliest_first_dt
  FROM ads a
  LEFT JOIN sales s
    ON  s.period_type = a.period_type AND s.country = a.country
    AND s.level_2 = a.level_2 AND s.level_3 = a.level_3
  LEFT JOIN new_cust n
    ON  n.period_type = a.period_type AND n.country = a.country
    AND n.level_2 = a.level_2 AND n.level_3 = a.level_3
),

/* components. Everything a lever needs, both periods, guarded. */
comp AS (
  SELECT
     b.*
    ,SAFE_DIVIDE(b.revenue_cur, NULLIF(b.spend_cur, 0))              AS roas_cur
    ,SAFE_DIVIDE(b.revenue_prv, NULLIF(b.spend_prv, 0))              AS roas_prv
    -- auction 3-lever set: ROAS = CVR * AOV / CPC
    ,SAFE_DIVIDE(b.bills_cur,   NULLIF(b.clicks_cur, 0))             AS cvr_cur
    ,SAFE_DIVIDE(b.bills_prv,   NULLIF(b.clicks_prv, 0))             AS cvr_prv
    ,SAFE_DIVIDE(b.revenue_cur, NULLIF(b.bills_cur, 0))              AS aov_cur
    ,SAFE_DIVIDE(b.revenue_prv, NULLIF(b.bills_prv, 0))              AS aov_prv
    ,SAFE_DIVIDE(b.spend_cur,   NULLIF(b.clicks_cur, 0))             AS cpc_cur
    ,SAFE_DIVIDE(b.spend_prv,   NULLIF(b.clicks_prv, 0))             AS cpc_prv
    -- universal 2-lever set: ROAS = AOV / CPO
    ,SAFE_DIVIDE(b.spend_cur,   NULLIF(b.bills_cur, 0))              AS cpo_cur
    ,SAFE_DIVIDE(b.spend_prv,   NULLIF(b.bills_prv, 0))              AS cpo_prv
    -- side metrics, not levers
    ,SAFE_DIVIDE(b.spend_cur,   NULLIF(b.new_customers_cur, 0))      AS cac_cur
    ,SAFE_DIVIDE(b.spend_prv,   NULLIF(b.new_customers_prv, 0))      AS cac_prv
    ,SAFE_DIVIDE(b.clicks_cur,  NULLIF(b.impressions_cur, 0))        AS ctr_cur
    ,SAFE_DIVIDE(b.clicks_prv,  NULLIF(b.impressions_prv, 0))        AS ctr_prv
    ,SAFE_DIVIDE(b.platform_revenue_cur, NULLIF(b.spend_gmvmax_cur, 0)) AS roas_platform_cur
    ,SAFE_DIVIDE(b.platform_revenue_prv, NULLIF(b.spend_gmvmax_prv, 0)) AS roas_platform_prv
    ,SAFE_DIVIDE(b.conversion_value_cur, NULLIF(b.spend_auction_cur, 0)) AS roas_conversion_cur
    ,SAFE_DIVIDE(b.conversion_value_prv, NULLIF(b.spend_auction_prv, 0)) AS roas_conversion_prv
    /* which Level 2 identity applies.
       Clicks are the problem: TikTok GMV Max reports spend and orders but no
       clicks and no impressions, so CVR and CPC do not exist for it. Any row
       carrying GMV Max spend therefore falls back to the 2-lever identity,
       which needs only orders. Both identities close on ROAS exactly. */
    ,CASE WHEN b.spend_gmvmax_cur > 0 OR b.spend_gmvmax_prv > 0 THEN 'aov_cpo'
          ELSE 'cvr_aov_cpc' END                                      AS driver_basis
  FROM base b
),

/* Level 1: Revenue = Spend x ROAS, interaction split evenly.

   (s1-s0)*r0  +  s0*(r1-r0)  +  (s1-s0)*(r1-r0)  ==  s1*r1 - s0*r0
   The third term is the interaction; half goes to each side, which is why the
   two contributions below sum to the revenue delta exactly. */
lvl1 AS (
  SELECT
     c.*
    ,c.revenue_cur - c.revenue_prv                                   AS revenue_delta
    ,SAFE_DIVIDE(c.revenue_cur, NULLIF(c.revenue_prv, 0)) - 1        AS revenue_pct

    /* The identity only holds where spend is non-zero in BOTH periods. With no
       prior spend there is no prior ROAS to hold constant, and with no current
       spend there is no current ROAS - revenue that still arrives is organic,
       and calling it a marketing lever would be a fabrication. Those rows are
       labelled and excluded from the additivity assertion rather than forced
       into a number. */
    ,CASE WHEN c.spend_cur = 0 AND c.spend_prv = 0 THEN 'no_spend'
          WHEN c.spend_prv = 0                     THEN 'no_prior_spend'
          WHEN c.spend_cur = 0                     THEN 'spend_stopped'
          ELSE 'ok' END                                              AS level1_status
    ,IF(c.spend_cur > 0 AND c.spend_prv > 0,
        (c.spend_cur - c.spend_prv) * c.roas_prv
          + 0.5 * (c.spend_cur - c.spend_prv) * (c.roas_cur - c.roas_prv),
        NULL)                                                        AS delta_from_spend
    ,IF(c.spend_cur > 0 AND c.spend_prv > 0,
        c.spend_prv * (c.roas_cur - c.roas_prv)
          + 0.5 * (c.spend_cur - c.spend_prv) * (c.roas_cur - c.roas_prv),
        NULL)                                                        AS delta_from_roas
  FROM comp c
),

/* Level 2: split delta_from_roas across the multiplicative components by
   log share (LMDI). Because ROAS is a product of the levers,
   LN(roas1/roas0) == sum of the individual log ratios exactly, so allocating
   in proportion to them is additive by construction. */
lvl2 AS (
  SELECT
     l.*
    ,CASE WHEN l.driver_basis = 'cvr_aov_cpc'
            AND l.cvr_cur > 0 AND l.cvr_prv > 0
            AND l.aov_cur > 0 AND l.aov_prv > 0
            AND l.cpc_cur > 0 AND l.cpc_prv > 0
          THEN LN(l.cvr_cur / l.cvr_prv) END                          AS w_cvr
    ,CASE WHEN (l.driver_basis = 'cvr_aov_cpc'
                 AND l.cvr_cur > 0 AND l.cvr_prv > 0 AND l.aov_cur > 0 AND l.aov_prv > 0
                 AND l.cpc_cur > 0 AND l.cpc_prv > 0)
             OR (l.driver_basis = 'aov_cpo'
                 AND l.aov_cur > 0 AND l.aov_prv > 0 AND l.cpo_cur > 0 AND l.cpo_prv > 0)
          THEN LN(l.aov_cur / l.aov_prv) END                          AS w_aov
    ,CASE WHEN l.driver_basis = 'cvr_aov_cpc'
            AND l.cvr_cur > 0 AND l.cvr_prv > 0
            AND l.aov_cur > 0 AND l.aov_prv > 0
            AND l.cpc_cur > 0 AND l.cpc_prv > 0
          THEN -LN(l.cpc_cur / l.cpc_prv) END                         AS w_cpc
    ,CASE WHEN l.driver_basis = 'aov_cpo'
            AND l.aov_cur > 0 AND l.aov_prv > 0
            AND l.cpo_cur > 0 AND l.cpo_prv > 0
          THEN -LN(l.cpo_cur / l.cpo_prv) END                         AS w_cpo
  FROM lvl1 l
),
lvl2w AS (
  SELECT
     x.*
    ,IFNULL(x.w_cvr,0) + IFNULL(x.w_aov,0) + IFNULL(x.w_cpc,0) + IFNULL(x.w_cpo,0) AS total_w
    ,CASE
       -- Level 2 cannot be better founded than Level 1
       WHEN x.level1_status <> 'ok'                            THEN x.level1_status
       WHEN x.driver_basis = 'cvr_aov_cpc' AND x.w_cvr IS NULL THEN 'insufficient_data'
       WHEN x.driver_basis = 'aov_cpo'     AND x.w_aov IS NULL THEN 'insufficient_data'
       -- ROAS effectively unchanged: the log shares cancel and the allocation
       -- becomes 0/0. delta_from_roas is ~0 anyway, so report it as such rather
       -- than dividing by a number that is noise.
       WHEN ABS(IFNULL(x.w_cvr,0) + IFNULL(x.w_aov,0) + IFNULL(x.w_cpc,0) + IFNULL(x.w_cpo,0)) < 1e-9
            THEN 'roas_unchanged'
       ELSE 'ok'
     END                                                              AS driver_confidence
  FROM lvl2 x
),

/* long format: two Level 1 rows, then two or three Level 2 rows */
drivers AS (
  SELECT y.*, d.driver_level, d.driver_name, d.contribution_vnd
  FROM lvl2w y
  CROSS JOIN UNNEST([
     STRUCT(1 AS driver_level, 'spend' AS driver_name, y.delta_from_spend AS contribution_vnd)
    ,STRUCT(1, 'roas',  y.delta_from_roas)
    ,STRUCT(2, 'cvr',   IF(y.driver_confidence = 'ok',
              y.delta_from_roas * SAFE_DIVIDE(y.w_cvr, NULLIF(y.total_w, 0)), NULL))
    ,STRUCT(2, 'aov',   IF(y.driver_confidence = 'ok',
              y.delta_from_roas * SAFE_DIVIDE(y.w_aov, NULLIF(y.total_w, 0)), NULL))
    ,STRUCT(2, 'cpc',   IF(y.driver_confidence = 'ok' AND y.driver_basis = 'cvr_aov_cpc',
              y.delta_from_roas * SAFE_DIVIDE(y.w_cpc, NULLIF(y.total_w, 0)), NULL))
    ,STRUCT(2, 'cpo',   IF(y.driver_confidence = 'ok' AND y.driver_basis = 'aov_cpo',
              y.delta_from_roas * SAFE_DIVIDE(y.w_cpo, NULLIF(y.total_w, 0)), NULL))
  ]) d
  -- a lever the identity does not use is not a row, it is absent
  WHERE NOT (d.driver_level = 2 AND d.driver_name = 'cvr' AND y.driver_basis <> 'cvr_aov_cpc')
    AND NOT (d.driver_level = 2 AND d.driver_name = 'cpc' AND y.driver_basis <> 'cvr_aov_cpc')
    AND NOT (d.driver_level = 2 AND d.driver_name = 'cpo' AND y.driver_basis <> 'aov_cpo')
)

SELECT
   period_type, period_start_date, period_end_date, prv_start_date, prv_end_date, elapsed_days
  ,country, level_1, level_2, level_3
  ,ads_channels, buying_types
  ,driver_level, driver_name, driver_basis, level1_status, driver_confidence
  ,contribution_vnd
  ,SAFE_DIVIDE(contribution_vnd, NULLIF(revenue_delta, 0))           AS contribution_share

   -- the movement being explained
  ,revenue_cur, revenue_prv, revenue_delta, revenue_pct
  ,delta_from_spend, delta_from_roas

   -- additivity, asserted in config
  ,revenue_delta - (delta_from_spend + delta_from_roas)              AS level1_residual
  ,CASE WHEN driver_confidence = 'ok' THEN
      delta_from_roas - (
        IFNULL(delta_from_roas * SAFE_DIVIDE(w_cvr, NULLIF(total_w,0)), 0)
      + IFNULL(delta_from_roas * SAFE_DIVIDE(w_aov, NULLIF(total_w,0)), 0)
      + IFNULL(delta_from_roas * SAFE_DIVIDE(w_cpc, NULLIF(total_w,0)), 0)
      + IFNULL(delta_from_roas * SAFE_DIVIDE(w_cpo, NULLIF(total_w,0)), 0))
   END                                                               AS level2_residual

   -- components, both periods
  ,spend_cur, spend_prv, spend_auction_cur, spend_auction_prv
  ,spend_gmvmax_cur, spend_gmvmax_prv
  ,clicks_cur, clicks_prv, impressions_cur, impressions_prv
  ,bills_cur, bills_prv, units_cur, units_prv
  ,roas_cur, roas_prv, cvr_cur, cvr_prv, aov_cur, aov_prv
  ,cpc_cur, cpc_prv, cpo_cur, cpo_prv, ctr_cur, ctr_prv
  ,new_customers_cur, new_customers_prv, cac_cur, cac_prv
  ,earliest_first_dt
  ,SAFE_DIVIDE(spend_cur, NULLIF(spend_prv,0)) - 1                   AS spend_pct
  ,SAFE_DIVIDE(roas_cur,  NULLIF(roas_prv,0))  - 1                   AS roas_pct

   -- platform-attributed, alongside, never summed with revenue_* or each other
  ,platform_orders_cur, platform_orders_prv
  ,platform_revenue_cur, platform_revenue_prv
  ,roas_platform_cur, roas_platform_prv
  ,conversions_cur, conversions_prv
  ,conversion_value_cur, conversion_value_prv
  ,roas_conversion_cur, roas_conversion_prv
FROM drivers