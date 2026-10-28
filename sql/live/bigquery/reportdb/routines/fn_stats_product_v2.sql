CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_stats_product_v2(i_type INT64, i_number_year_back INT64, i_days_range INT64, i_avg_units_sold_expect INT64, i_FromDate DATE, i_ToDate DATE)
OPTIONS(
  description="Stock-forecasting scorecard per SKU: sell-through, velocity, DOH,\ncolour bucket, and a deterministic overstock / stockout alert engine.\nFeeds reportdb.sp_ai_product_stock_insights. Refactor of fn_stats_product (v2).")
AS
WITH
-------------------------------------------------------------------------------
-- 0. Tunable business thresholds. Edit here, nowhere else.
-------------------------------------------------------------------------------
const AS (
  SELECT
     14   AS k_stockout_grace_days        -- days at zero stock after which a SKU is "inactive"
    ,56   AS k_new_product_grace_days     -- 8 weeks: too young to be judged a slow mover
    ,60   AS k_doh_healthy_max            -- <= 60d cover  = healthy (normal SKU)
    ,150  AS k_doh_healthy_max_top        -- <= 150d cover = healthy (top seller: higher buffer allowed)
    ,90  AS k_doh_watch_max              -- <= 90d cover = watch
    ,150  AS k_doh_severe_max             -- <  360d cover = severe; >= 360d = dead stock
    ,60   AS k_target_cover_days          -- planning target: stock we WANT to hold (normal SKU)
    ,120  AS k_target_cover_days_top      -- planning target: stock we WANT to hold (top seller)
    ,0.25 AS k_sell_through_low           -- sell-through band cutoffs
    ,0.50 AS k_sell_through_mid

    -- --- Top-seller selection (Step 1) --------------------------------------
    ,10   AS k_top_n_all_time             -- all-time top N, live SKUs only
    ,20   AS k_top_n_recent               -- top N in each recent window
    ,10    AS k_top_n_collection           -- top N within each collection_bst (see DECISION 1)
    ,30   AS k_recent_window_1_days       -- recent window 1 = last 30 days
    ,60   AS k_recent_window_2_days       -- recent window 2 = last 60 days

    -- --- Stockout trigger points (Step 3) -----------------------------------
    ,14   AS k_stockout_imminent_days     -- normal SKU: imminent below 14d cover
    ,30   AS k_stockout_risk_days         -- normal SKU: at risk below 30d cover
    ,30   AS k_stockout_imminent_days_top -- top seller: imminent below 30d cover (fires earlier)
    ,60   AS k_stockout_risk_days_top     -- top seller: at risk below 60d cover (fires earlier)
    ,0.2  AS k_min_velocity_for_alert     -- normal SKUs need real movement to raise a stockout alert;
                                          -- top sellers are exempt from this gate by design

    -- --- Colour bucket score cut-points (Step 2) ----------------------------
    ,11   AS k_score_green                -- normal SKU cut-points (max score = 12)
    ,7    AS k_score_yellow
    ,4    AS k_score_red
    ,9    AS k_score_green_top            -- top seller cut-points: easier to stay green
    ,6    AS k_score_yellow_top
    ,3    AS k_score_red_top
    ,TRUE AS k_top_stockout_floor         -- see DECISION 2; FALSE = literal Step 2 behaviour
)

-------------------------------------------------------------------------------
-- 1. Base metrics from raw inventory summary.
--    Grain: period_date x variation_code x warehouse x channel.
-------------------------------------------------------------------------------
,base AS (
  SELECT
     f.*
    ,c.*
    -- Inactive: discontinued, or out of stock long enough that its metrics are noise.
    ,IF(f.is_sale_end = 1 OR f.emty_stock_days > c.k_stockout_grace_days, 1, 0) AS is_inactive
    -- Target daily velocity implied by the caller's expectation for the whole period.
    ,SAFE_DIVIDE(i_avg_units_sold_expect, f.days_range) AS expected_velocity
    ,SAFE_DIVIDE(f.units_sold_day_range, f.days_range)  AS velocity_raw
    ,IFNULL(
       SAFE_DIVIDE(f.units_sold_day_range, f.units_sold_day_range + f.sl_ton_kho)
      ,0
     ) AS sell_through_rate
  FROM `marine-cycle-484213-b4.reportdb.sku_inventory_master` f
  CROSS JOIN const c
  WHERE report_type = i_type
  AND  (i_FromDate IS NULL OR period_date >= i_FromDate) 
  AND  (i_ToDate IS NULL OR period_date <= i_ToDate)  
  
)

-------------------------------------------------------------------------------
-- 2. STEP 1 - Top seller identification.
--    Everything below collapses to ONE ROW PER variation_code before ranking,
--    which is what makes the join back to `base` safe.
-------------------------------------------------------------------------------

-- 2a. Anchor the recent windows on the latest period actually present in the call.
--     `days_covered` lets the QA appendix confirm the 30d/60d windows are really
--     30 and 60 days wide -- if the caller passes a 5-day i_FromDate..i_ToDate,
--     both windows collapse to 5 days and the two categories become identical.
,window_anchor AS (
  SELECT
     MAX(period_date)                                        AS anchor_date
    ,DATE_DIFF(MAX(period_date), MIN(period_date), DAY) + 1  AS days_covered
  FROM base
)

-- 2c. SKU-grain sales. `units_sold` is the DAILY figure per row and is additive;
--     `units_sold_day_range` is a rolling snapshot and must NOT be summed.
,sku_sales AS (
  SELECT
     b.variation_code
    ,ANY_VALUE(collection_bst)    AS collection_bst
    ,MAX(b.is_sale_end)           AS is_sale_end_sku
    ,SUM(IFNULL(b.units_sold, 0)) AS units_all_time
    ,SUM(IF(b.period_date > DATE_SUB(w.anchor_date, INTERVAL b.k_recent_window_1_days DAY),
            IFNULL(b.units_sold, 0), 0)) AS units_recent_30d
    ,SUM(IF(b.period_date > DATE_SUB(w.anchor_date, INTERVAL b.k_recent_window_2_days DAY),
            IFNULL(b.units_sold, 0), 0)) AS units_recent_60d
  FROM base b
  CROSS JOIN window_anchor w
  WHERE b.variation_code IS NOT NULL
  GROUP BY b.variation_code
)

-- 2d. The four rankings. ROW_NUMBER (not DENSE_RANK) so "top 10" means 10 SKUs.
--     PARTITION BY <eligibility boolean> confines the ranking to eligible SKUs in
--     a single pass; the outer CASE nulls out everyone else.
,top_sales_sku AS (
  SELECT
     s.variation_code
    ,s.units_all_time
    ,s.units_recent_30d
    ,s.units_recent_60d
    ,s.collection_bst

    -- Category 1: all-time top N. Sale-ended SKUs are excluded before ranking.
    ,CASE WHEN s.is_sale_end_sku = 0 AND s.units_all_time > 0
          THEN ROW_NUMBER() OVER (
                 PARTITION BY (s.is_sale_end_sku = 0 AND s.units_all_time > 0)
                 ORDER BY s.units_all_time DESC, s.variation_code)
     END AS rank_all_time

    -- Category 2: top N over the last 30 days.
    ,CASE WHEN s.units_recent_30d > 0
          THEN ROW_NUMBER() OVER (
                 PARTITION BY (s.units_recent_30d > 0)
                 ORDER BY s.units_recent_30d DESC, s.variation_code)
     END AS rank_30d

    -- Category 3: top N over the last 60 days.
    ,CASE WHEN s.units_recent_60d > 0
          THEN ROW_NUMBER() OVER (
                 PARTITION BY (s.units_recent_60d > 0)
                 ORDER BY s.units_recent_60d DESC, s.variation_code)
     END AS rank_60d

    -- Category 4: top N within each collection_bst, live SKUs only.
    ,CASE WHEN s.collection_bst IS NOT NULL AND s.is_sale_end_sku = 0 AND s.units_all_time > 0
          THEN ROW_NUMBER() OVER (
                 PARTITION BY s.collection_bst,
                              (s.is_sale_end_sku = 0 AND s.units_all_time > 0)
                 ORDER BY s.units_all_time DESC, s.variation_code)
     END AS rank_in_collection
  FROM sku_sales s
)

-- 2e. Ranks -> flags + human-readable qualification strings (EN and VI).
--     Still exactly one row per variation_code.
,top_seller_flagged AS (
  SELECT
     t.variation_code
    ,t.units_recent_30d
    ,t.units_recent_60d

    ,IFNULL(t.rank_all_time      <= c.k_top_n_all_time,   FALSE) AS is_all_time_top_10
    ,IFNULL(t.rank_30d           <= c.k_top_n_recent,     FALSE) AS is_top_20_30d
    ,IFNULL(t.rank_60d           <= c.k_top_n_recent,     FALSE) AS is_top_20_60d
    ,IFNULL(t.rank_in_collection <= c.k_top_n_collection, FALSE) AS is_top_by_collection

    -- Qualify under ANY category -> TRUE.
    ,(   IFNULL(t.rank_all_time      <= c.k_top_n_all_time,   FALSE)
      OR IFNULL(t.rank_30d           <= c.k_top_n_recent,     FALSE)
      OR IFNULL(t.rank_60d           <= c.k_top_n_recent,     FALSE)
      OR IFNULL(t.rank_in_collection <= c.k_top_n_collection, FALSE)) AS is_top_seller

    ,ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST([
        IF(IFNULL(t.rank_all_time <= c.k_top_n_all_time, FALSE),
           FORMAT('All-time top %d (#%d)', c.k_top_n_all_time, t.rank_all_time), NULL),
        IF(IFNULL(t.rank_30d <= c.k_top_n_recent, FALSE),
           FORMAT('%d-day top %d (#%d)', c.k_recent_window_1_days, c.k_top_n_recent, t.rank_30d), NULL),
        IF(IFNULL(t.rank_60d <= c.k_top_n_recent, FALSE),
           FORMAT('%d-day top %d (#%d)', c.k_recent_window_2_days, c.k_top_n_recent, t.rank_60d), NULL),
        IF(IFNULL(t.rank_in_collection <= c.k_top_n_collection, FALSE),
           FORMAT('Top %d in collection %s (#%d)', c.k_top_n_collection, t.collection_bst, t.rank_in_collection), NULL)
      ]) AS x WHERE x IS NOT NULL), ' | ') AS top_seller_categories

    ,ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST([
        IF(IFNULL(t.rank_all_time <= c.k_top_n_all_time, FALSE),
           FORMAT('Top %d toàn thời gian (#%d)', c.k_top_n_all_time, t.rank_all_time), NULL),
        IF(IFNULL(t.rank_30d <= c.k_top_n_recent, FALSE),
           FORMAT('Top %d trong %d ngày (#%d)', c.k_top_n_recent, c.k_recent_window_1_days, t.rank_30d), NULL),
        IF(IFNULL(t.rank_60d <= c.k_top_n_recent, FALSE),
           FORMAT('Top %d trong %d ngày (#%d)', c.k_top_n_recent, c.k_recent_window_2_days, t.rank_60d), NULL),
        IF(IFNULL(t.rank_in_collection <= c.k_top_n_collection, FALSE),
           FORMAT('Top %d của BST %s (#%d)', c.k_top_n_collection, t.collection_bst, t.rank_in_collection), NULL)
      ]) AS x WHERE x IS NOT NULL), ' | ') AS top_seller_categories_vi
  FROM top_sales_sku t
  CROSS JOIN const c
)

-------------------------------------------------------------------------------
-- 3. Derived metrics, with per-SKU thresholds resolved from the top-seller flag.
--    The join below is 1:1 -- top_seller_flagged is SKU-grain.
-------------------------------------------------------------------------------
,derived AS (
  SELECT
     b.*
    ,IFNULL(ts.is_top_seller,          FALSE) AS is_top_seller
    ,IFNULL(ts.is_all_time_top_10,     FALSE) AS is_all_time_top_10
    ,IFNULL(ts.is_top_20_30d,          FALSE) AS is_top_20_30d
    ,IFNULL(ts.is_top_20_60d,          FALSE) AS is_top_20_60d
    ,IFNULL(ts.is_top_by_collection,   FALSE) AS is_top_by_collection
    ,IFNULL(ts.top_seller_categories,    '')  AS top_seller_categories
    ,IFNULL(ts.top_seller_categories_vi, '')  AS top_seller_categories_vi
    ,IFNULL(ts.units_recent_30d, 0)           AS sku_units_last_30d
    ,IFNULL(ts.units_recent_60d, 0)           AS sku_units_last_60d

    -- Threshold set actually applied to this row (exported so the numbers are auditable).
    ,IF(IFNULL(ts.is_top_seller,FALSE), b.k_target_cover_days_top,      b.k_target_cover_days)      AS target_cover_days_adj
    ,IF(IFNULL(ts.is_top_seller,FALSE), b.k_doh_healthy_max_top,        b.k_doh_healthy_max)        AS doh_healthy_max_adj
    ,IF(IFNULL(ts.is_top_seller,FALSE), b.k_stockout_imminent_days_top, b.k_stockout_imminent_days) AS stockout_imminent_days_adj
    ,IF(IFNULL(ts.is_top_seller,FALSE), b.k_stockout_risk_days_top,     b.k_stockout_risk_days)     AS stockout_risk_days_adj

    -- Days of cover:
    ,IF(b.sl_ton_kho <= 0, 0, SAFE_DIVIDE(b.sl_ton_kho, b.velocity_raw)) AS doh_raw
    ,IF(b.sl_ton_kho > 0 AND IFNULL(b.velocity_raw, 0) = 0, 1, 0)        AS doh_is_infinite

    -- Stock above the planning target. Top sellers are held to a 120-day target,
    -- so less of their stock counts as excess.
    ,GREATEST(
       b.sl_ton_kho - CAST(CEIL(IFNULL(b.velocity_raw, 0)
         * IF(IFNULL(ts.is_top_seller,FALSE), b.k_target_cover_days_top, b.k_target_cover_days)) AS INT64)
      ,0
     ) AS excess_units
  FROM base b
  LEFT JOIN top_seller_flagged ts ON b.variation_code = ts.variation_code
)

-------------------------------------------------------------------------------
-- 4. Bands. DOH_band uses doh_healthy_max_adj, so a top seller sitting on 150
--    days of cover still scores 4 where a normal SKU would drop to 3.
-------------------------------------------------------------------------------
,banded AS (
  SELECT
     d.*
    ,ROUND(d.doh_raw, 0)                        AS DOH
    ,d.excess_units * IFNULL(d.retail_price, 0) AS excess_value

    ,CASE
       WHEN d.is_inactive = 1                          THEN 0
       WHEN d.sell_through_rate = 0                    THEN 1
       WHEN d.sell_through_rate < d.k_sell_through_low THEN 2
       WHEN d.sell_through_rate < d.k_sell_through_mid THEN 3
       ELSE 4
     END AS sell_through_band

    ,CASE
       WHEN d.is_inactive = 1                        THEN 0
       WHEN d.velocity_raw < d.expected_velocity / 4 THEN 1
       WHEN d.velocity_raw < d.expected_velocity / 2 THEN 2
       WHEN d.velocity_raw < d.expected_velocity     THEN 3
       ELSE 4
     END AS velocity_band

    ,CASE
       WHEN d.is_inactive = 1                                              THEN 0
       -- Sold out: good if it was selling fast, dead if it never moved.
       WHEN d.sl_ton_kho <= 0 AND d.velocity_raw >= d.expected_velocity     THEN 4
       WHEN d.sl_ton_kho <= 0 AND d.velocity_raw <  d.expected_velocity / 4 THEN 1
       WHEN d.sl_ton_kho <= 0                                              THEN 3
       WHEN d.doh_is_infinite = 1                                          THEN 1
       WHEN d.doh_raw <= d.doh_healthy_max_adj                             THEN 4  -- 150d for top sellers, 90d otherwise
       WHEN d.doh_raw <= d.k_doh_watch_max                                 THEN 3
       WHEN d.doh_raw <  d.k_doh_severe_max                                THEN 2
       ELSE 1
     END AS DOH_band
  FROM derived d
)

-------------------------------------------------------------------------------
-- 5. STEP 2 - Scorecard and colour buckets.
--    Top sellers get (a) relaxed score cut-points, (b) the 150-day healthy
--    ceiling already applied in DOH_band, and (c) a stockout floor that stops a
--    green badge being printed over an imminent stockout (see DECISION 2).
-------------------------------------------------------------------------------
,scored AS (
  SELECT
     b.*
    ,b.sell_through_band + b.velocity_band + b.DOH_band AS health_score

    ,CASE
       -- Discontinued / long-dead SKUs drop out, EXCEPT live top sellers, whose
       -- stockout is the whole point of the flag.
       WHEN b.is_inactive = 1
            AND NOT (b.k_top_stockout_floor AND b.is_top_seller AND b.is_sale_end = 0)
            THEN 'NO STOCK OR SALE ENDED'

       -- Stockout floor, top sellers only.
       WHEN b.k_top_stockout_floor AND b.is_top_seller AND b.is_sale_end = 0 AND b.sl_ton_kho <= 0
            THEN '4-BLACK'
       WHEN b.k_top_stockout_floor AND b.is_top_seller AND b.doh_is_infinite = 0
            AND b.doh_raw < b.stockout_imminent_days_adj
            THEN '3-RED'
       WHEN b.k_top_stockout_floor AND b.is_top_seller AND b.doh_is_infinite = 0
            AND b.doh_raw < b.stockout_risk_days_adj
            THEN '2-YELLOW'

       -- Relaxed cut-points for top sellers (9 / 6 / 3 out of a maximum 12).
       WHEN b.is_top_seller
            AND (b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_green_top
            THEN '1-GREEN'
       WHEN b.is_top_seller
            AND ((b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_yellow_top
                 OR b.product_days_since_launch <= b.k_new_product_grace_days)
            THEN '2-YELLOW'
       WHEN b.is_top_seller
            AND (b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_red_top
            THEN '3-RED'
       WHEN b.is_top_seller THEN '4-BLACK'

       -- Standard cut-points (11 / 7 / 4).
       WHEN (b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_green  THEN '1-GREEN'
       WHEN (b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_yellow
            OR b.product_days_since_launch <= b.k_new_product_grace_days             THEN '2-YELLOW'
       WHEN (b.sell_through_band + b.velocity_band + b.DOH_band) >= b.k_score_red    THEN '3-RED'
       ELSE '4-BLACK'
     END AS colour_bucket

    -- Overstock exposure (0-100)
    ,CAST(ROUND(
        50 * LEAST(IFNULL(b.doh_raw, b.k_doh_severe_max) / b.k_doh_severe_max, 1)
      + 30 * (1 - LEAST(IFNULL(SAFE_DIVIDE(b.velocity_raw, b.expected_velocity), 0), 1))
      + 20 * PERCENT_RANK() OVER (
               PARTITION BY b.period_date
               ORDER BY b.excess_units * IFNULL(b.retail_price, 0)
             )
     , 0) AS INT64) AS overstock_risk_score
  FROM banded b
)

-------------------------------------------------------------------------------
-- 6. STEP 3 - Alert engine.
--    Top sellers trip STOCKOUT_IMMINENT at 30 days of cover and STOCKOUT_RISK at
--    60, versus 14 and 30 for normal SKUs, and are exempt from the
--    k_min_velocity_for_alert gate so a quiet week cannot mute the alert.
-------------------------------------------------------------------------------
,alerted AS (
  SELECT
     s.*
    ,CASE
       -- Highest-value signal in the dataset: a live top seller at zero stock.
       -- Must precede the inactive branch, which would otherwise swallow it.
       WHEN s.is_top_seller AND s.is_sale_end = 0 AND s.sl_ton_kho <= 0     THEN 'STOCKOUT_NOW'

       WHEN s.is_inactive = 1                                              THEN 'NO_STOCK_OR_ENDED'

       -- Overstock family
       WHEN s.doh_is_infinite = 1 AND s.sl_ton_kho > 0                     THEN 'DEAD_STOCK'
       WHEN s.doh_raw >= s.k_doh_severe_max AND s.velocity_band <= 1        THEN 'OVERSTOCK_CRITICAL'
       WHEN s.doh_raw >  s.k_doh_watch_max  AND s.velocity_band <= 2        THEN 'OVERSTOCK_HIGH'
       WHEN s.doh_raw >  s.doh_healthy_max_adj AND s.velocity_band <= 3     THEN 'OVERSTOCK_WATCH'

       -- Stockout family, top sellers first (earlier triggers, no velocity gate)
       WHEN s.is_top_seller AND s.doh_is_infinite = 0
            AND s.doh_raw < s.stockout_imminent_days_adj                    THEN 'STOCKOUT_IMMINENT'
       WHEN s.is_top_seller AND s.doh_is_infinite = 0
            AND s.doh_raw < s.stockout_risk_days_adj                        THEN 'STOCKOUT_RISK'

       -- Stockout family, normal SKUs
       WHEN s.sl_ton_kho <= 0
            AND s.velocity_raw > s.k_min_velocity_for_alert                 THEN 'STOCKOUT_NOW'
       WHEN s.doh_raw < s.stockout_imminent_days_adj
            AND s.velocity_raw > s.k_min_velocity_for_alert                 THEN 'STOCKOUT_IMMINENT'
       WHEN s.doh_raw < s.stockout_risk_days_adj
            AND s.velocity_raw > s.k_min_velocity_for_alert                 THEN 'STOCKOUT_RISK'

       ELSE 'HEALTHY'
     END AS alert_code

    ,CASE
       WHEN s.is_inactive = 1
            AND NOT (s.k_top_stockout_floor AND s.is_top_seller AND s.is_sale_end = 0) THEN 0
       WHEN s.doh_is_infinite = 1 AND s.sl_ton_kho > 0 THEN 50
       WHEN s.doh_raw >= s.k_doh_severe_max            THEN 40
       WHEN s.doh_raw >  s.k_doh_watch_max             THEN 30
       WHEN s.doh_raw >  s.doh_healthy_max_adj         THEN 15  -- top sellers only discounted past 150d
       ELSE 0
     END AS suggested_discount_pct
  FROM scored s
)

-------------------------------------------------------------------------------
-- 7. Main export output query.
--    Existing columns keep their original names, order and positions.
--    Eight new columns are appended after `comments`.
-------------------------------------------------------------------------------
SELECT
  IF(i_type = 0, DATE_SUB(CURRENT_DATE(), INTERVAL sort_desc DAY), DATE_ADD(CURRENT_DATE(), INTERVAL -1 DAY)) AS period_date
  ,period_date AS updated_date
  ,sort_desc
  ,is_latest
  ,product_code
  ,variation_code
  ,variation_attributes
  ,product_name
  ,product_days_since_launch
  ,days_range
  ,is_sale_end
  ,is_inactive
  ,is_top_seller                                     -- Step 1: top-seller flag
  ,retail_price
  ,warehouse_id
  ,warehouse_name
  ,order_sources_name
  ,sale_channel
  ,sale_channel_details
  ,order_year

  -- Stock & flow
  ,sl_nhap_moi_tu_sx
  ,sl_nhap_kho
  ,sl_ton_kho
  ,sl_ton_kho_diff
  ,tong_gia_tri_hang_ton_kho_theo_gia_ban
  ,ton_kho_running_days
  ,emty_stock_days

  -- Sales
  ,units_sold
  ,units_sold_day_range
  ,units_sold_since_restock
  ,sales_revenue
  ,revenue

  -- Rates
  ,ROUND(sell_through_rate, 4)  AS sell_through_rate
  ,ROUND(velocity_raw, 4)       AS sale_velocity
  ,ROUND(expected_velocity, 4)  AS expected_velocity
  ,DOH
  ,doh_is_infinite

  -- Scorecard
  ,sell_through_band
  ,velocity_band
  ,DOH_band
  ,health_score
  ,colour_bucket

  -- Alerting
  ,alert_code
  ,CASE alert_code
     WHEN 'DEAD_STOCK'         THEN 1
     WHEN 'OVERSTOCK_CRITICAL' THEN 1
     WHEN 'STOCKOUT_NOW'       THEN 1
     WHEN 'OVERSTOCK_HIGH'     THEN 2
     WHEN 'STOCKOUT_IMMINENT'  THEN 2
     WHEN 'OVERSTOCK_WATCH'    THEN 3
     WHEN 'STOCKOUT_RISK'      THEN 3
     ELSE 4
   END AS alert_severity        -- 1 = act now, 4 = informational
  ,overstock_risk_score
  ,excess_units
  ,excess_value
  ,suggested_discount_pct

  -- STEP 4: rule-based comments. For a top seller the comment states the flag,
  -- the category or categories it qualified under, and the exact thresholds that
  -- were raised as a result.
  ,CASE
     WHEN is_top_seller AND is_sale_end = 0 AND sl_ton_kho <= 0 THEN
       FORMAT('🔥 TOP SELLER (%s) — HẾT HÀNG. Ngưỡng tồn kho đã nâng lên (tồn mục tiêu %d ngày, cảnh báo sớm từ %d ngày). Ưu tiên nhập bổ sung ngay.',
              top_seller_categories_vi, target_cover_days_adj, stockout_risk_days_adj)

     WHEN is_inactive = 1 THEN
       'SKU đã ngưng bán hoặc hết hàng kéo dài — không tính vào đánh giá tốc độ bán'

     WHEN is_top_seller THEN
       FORMAT('🔥 TOP SELLER (%s) — Ngưỡng tồn kho đã nâng lên: tồn mục tiêu %d ngày (thay vì %d), ngưỡng tồn khoẻ %d ngày (thay vì %d), cảnh báo hết hàng từ %d/%d ngày (thay vì %d/%d). %s',
              top_seller_categories_vi,
              target_cover_days_adj,      k_target_cover_days,
              doh_healthy_max_adj,        k_doh_healthy_max,
              stockout_imminent_days_adj, stockout_risk_days_adj,
              k_stockout_imminent_days,   k_stockout_risk_days,
              CASE colour_bucket
                WHEN '1-GREEN'  THEN FORMAT('Tồn kho đang ở mức tốt (%d ngày DOH).', CAST(IFNULL(DOH,0) AS INT64))
                WHEN '2-YELLOW' THEN FORMAT('Tồn kho cần chú ý (%d ngày DOH) — lên kế hoạch tái nhập sớm.', CAST(IFNULL(DOH,0) AS INT64))
                WHEN '3-RED'    THEN FORMAT('Tồn kho thấp (%d ngày DOH) — ưu tiên nhập hàng khẩn cấp.', CAST(IFNULL(DOH,0) AS INT64))
                ELSE 'Cảnh báo thiếu hụt nghiêm trọng — cần xử lý ngay.'
              END)

     WHEN colour_bucket = '1-GREEN'  THEN FORMAT('SKU bán chạy, tồn kho đủ bán khoảng %d ngày tới', CAST(IFNULL(DOH,0) AS INT64))
     WHEN colour_bucket = '2-YELLOW' THEN FORMAT('SKU bán ở mức bình thường, tồn kho đủ khoảng %d ngày tới', CAST(IFNULL(DOH,0) AS INT64))
     WHEN colour_bucket = '3-RED'    THEN FORMAT('SKU bán chậm, tồn %d ngày — cần đẩy doanh số/xả tồn, ưu tiên clearance', CAST(IFNULL(DOH,0) AS INT64))
     WHEN colour_bucket = '4-BLACK'  THEN 'SKU gần như không bán — xem xét markdown sâu, bundle hoặc ngừng kinh doanh'
     ELSE 'N/A'
   END AS comments

  -- New columns (appended, nothing above is displaced)
  ,is_all_time_top_10
  ,is_top_20_30d
  ,is_top_20_60d
  ,is_top_by_collection
  ,top_seller_categories        -- English, e.g. 'All-time top 10 (#3) | 30-day top 20 (#7)'
  ,collection_bst
  ,sku_units_last_30d
  ,sku_units_last_60d
FROM alerted;
