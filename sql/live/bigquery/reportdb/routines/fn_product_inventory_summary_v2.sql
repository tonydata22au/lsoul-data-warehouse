CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_product_inventory_summary_v2(i_type INT64, i_number_year_back INT64, i_days_range INT64, i_FromDate DATE, i_ToDate DATE)
OPTIONS(
  description="Product / SKU inventory + sales fact table.\ni_type = 0 -> one row per (period_date, variation_code, warehouse_id).\ni_type = 1 -> one row per variation_code at its latest period_date, stock summed across warehouses,\n              sales accumulated to lifetime totals.")
AS
WITH
-------------------------------------------------------------------------------
-- 0. Constants. One place to edit warehouse IDs and cutover dates.
-------------------------------------------------------------------------------
const AS (
  SELECT
     '76be7836-6dc5-4b1c-9e48-b18e43127453' AS wh_china_backup_id
    ,'878504e9-fb75-4870-8504-b2ecdbc097ba' AS wh_thai_backup_id
    ,DATE '2026-06-01'                      AS china_relabel_from
    ,DATE '2026-02-13'                      AS thai_relabel_from
    ,'Kho Trung Quốc (nguồn Pancake + Dianplus + Jushuitan)' AS wh_china_label
    ,'Kho Thái Lan (nguồn Pancake + Scale-Up Fulfilment)'    AS wh_thai_label
    -- SKU prefixes that are not sellable finished goods (gifts, samples, packaging...)
    ,['TG','HT','HN','HH','TD']             AS excluded_sku_prefixes
    ,GREATEST(IFNULL(i_days_range, 30), 1)  AS days_range_param
)

-------------------------------------------------------------------------------
-- 1. SKU dimension: exactly ONE row per variation. No warehouse columns here.
--    (v1 joined the warehouse-level CTE as if it were SKU-level -> row fan-out.)
-------------------------------------------------------------------------------
,dim_variation AS (
  SELECT DISTINCT
     variation_code
    ,product_code
    ,product_name
    ,TRIM(CONCAT(product_name, ' ', product_attributes)) AS variation_attributes
    ,COALESCE(category,
     CASE WHEN REGEXP_CONTAINS(variation_code, r'^(XHS-|[0-9]{6,})') THEN 'EXTERNAL SKU'
          ELSE 'UNMAPPED' END)                       AS category
    ,COALESCE(sub_category,'Not in product master')  AS sub_category
    ,collection_bst
    ,product_launch_date
    ,retail_price
    ,is_sale_end
  FROM `marine-cycle-484213-b4.reportdb.fn_dim_sku`()
)

-------------------------------------------------------------------------------
-- 2. SKU x warehouse dimension: on-hand fallback when the fact stream has no row.
-------------------------------------------------------------------------------
,variation_wh AS (
    SELECT
     variation_display_id         
    ,DATE(vw.updated_at)          AS updated_at
    ,vw.warehouse_id
    ,w.warehouse_name
    ,w.warehouse_type
    ,w.country
    ,SUM(IFNULL(vw.actual_remain_qty, 0)) AS actual_remain_qty
  FROM `marine-cycle-484213-b4.core_pancake.core_variations` v
  LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variation_warehouses` vw ON v.variation_id = vw.variation_id
  LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_warehouse` w ON w.warehouse_id = vw.warehouse_id
  GROUP BY 1,2,3,4,5,6
)

,dim_variation_wh AS (
    SELECT
     v.variation_code
    ,vw.updated_at
    ,vw.warehouse_id
    ,vw.warehouse_name
    ,vw.warehouse_type
    ,vw.country
    ,SUM(IFNULL(vw.actual_remain_qty, 0)) AS actual_remain_qty
  FROM dim_variation v
  LEFT JOIN variation_wh vw ON v.variation_code = vw.variation_display_id
  GROUP BY 1,2,3,4,5,6
)

-------------------------------------------------------------------------------
-- 3. Fact sources. Explicit column list per branch (v1's SELECT * in the final
--    UNION ALL silently depended on column ORDER). period_date CAST to DATE in
--    every branch. src_priority makes intra-day ordering deterministic so the
--    forward fill in step 5 is reproducible: sales (0) resolve before stock (1).
-------------------------------------------------------------------------------
,src_union AS (
  -- 3a. Pancake / local warehouses
  SELECT
    DATE(i.inserted_at) AS period_date
    ,1                            AS src_priority
    ,variation_code
    ,CAST(NULL AS STRING) AS product_name
    ,CAST(NULL AS FLOAT64) AS retail_price
    ,i.warehouse_id
    ,i.warehouse_name
    ,i.country AS warehouse_country
    ,IFNULL(i.sl_nhap_moi_tu_sx,0) AS sl_nhap_moi_tu_sx
    ,IFNULL(i.sl_nhap_kho,0) AS sl_nhap_kho
    ,CASE
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at)) <> sl_ton_kho
    THEN sl_ton_kho - LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at))
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at)) IS NULL
    THEN sl_ton_kho
    ELSE 0 END AS stock_level_raw   -- absolute level, not a delta
    ,CAST(NULL AS STRING)         AS order_sources_name
    ,CAST(NULL AS STRING)         AS sale_channel
    ,CAST(NULL AS STRING)         AS sale_channel_details
    ,CAST(NULL AS INT64)          AS order_year
    ,0                            AS sales_revenue
    ,0                            AS revenue
    ,0                            AS units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_product_variations_warehouse_summary`(1, 0, '') i 
  WHERE (i.warehouse_type NOT IN ('NONE','M') or  i.warehouse_type IS NULL 
  -- OR i.warehouse_id = '1a21d42d-d648-4fdd-9095-932fceb08a2d' --Thêm Kho hàng lỗi
  )

  UNION ALL

  -- 3b. China warehouse
  SELECT
     CAST(i.updated_at AS DATE)
    ,1
    ,i.variation_code
    ,i.product_name
    ,i.retail_price
    ,i.pancake_warehouse_id
    ,i.warehouse_name
    ,country
    ,0
    ,i.sl_nhap_kho
    ,CASE 
        WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))  <> sl_ton_kho
        THEN sl_ton_kho - LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))
        WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))  IS NULL
        THEN sl_ton_kho
    ELSE 0 END AS sl_ton_kho
    ,CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS INT64)
    ,0, 0, 0
  FROM `marine-cycle-484213-b4.reportdb.fn_china_product_inventory`(0, i_number_year_back) i

  UNION ALL

  -- 3c. Thailand warehouse
  SELECT
     CAST(i.updated_at AS DATE)
    ,1
    ,i.sku
    ,i.product_name
    ,i.retail_price
    ,i.warehouse_id
    ,i.warehouse_name
    ,country
    ,0
    ,i.sl_nhap_kho
    ,CASE 
      WHEN LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))  <> stock_on_hand
      THEN stock_on_hand - LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))
      WHEN LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))  IS NULL
      THEN stock_on_hand
      ELSE 0 END AS sl_ton_kho
    ,CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS INT64)
    ,0, 0, 0
  FROM `marine-cycle-484213-b4.reportdb.fn_thailand_product_inventory`(0, i_number_year_back) i

  UNION ALL

  -- 3d. Sales. NULL stock_level_raw -> carries the last known level forward (step 5).
  SELECT
     o.period_date
    ,0
    ,o.variation_code
    ,o.product_name
    ,o.retail_price
    ,o.warehouse_id
    ,o.warehouse_name
    ,o.country
    ,0
    ,0
    ,CAST(NULL AS INT64)
    ,o.level_1
    ,o.level_2
    ,o.level_3
    ,EXTRACT(YEAR FROM period_date)
    ,o.sales_revenue_vn
    ,o.revenue_vn
    ,o.units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_order_sku_warehouse_master`(i_number_year_back,0) o
)

-------------------------------------------------------------------------------
-- 4. Filter + warehouse relabelling. Filters run before any window function.
-------------------------------------------------------------------------------
,src_filtered AS (
  SELECT
     s.period_date
    ,s.src_priority
    ,s.variation_code
    ,s.product_name
    ,s.retail_price
    ,s.warehouse_id
    ,CASE
       WHEN s.period_date >= c.china_relabel_from AND s.warehouse_id = c.wh_china_backup_id THEN c.wh_china_label
       WHEN s.period_date >= c.thai_relabel_from  AND s.warehouse_id = c.wh_thai_backup_id  THEN c.wh_thai_label
       ELSE s.warehouse_name
     END AS warehouse_name
    ,s.warehouse_country
    ,s.sl_nhap_moi_tu_sx
    ,s.sl_nhap_kho
    ,SUM(s.stock_level_raw) OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stock_level_raw
    ,s.order_sources_name
    ,s.sale_channel
    ,s.sale_channel_details
    ,s.order_year
    ,s.sales_revenue
    ,s.revenue
    ,s.units_sold
  FROM src_union s
  CROSS JOIN const c
  WHERE SUBSTR(s.variation_code, 1, 2) NOT IN UNNEST(c.excluded_sku_prefixes)
    AND (s.retail_price IS NULL OR s.retail_price <> 0)
)

-------------------------------------------------------------------------------
-- 5. Collapse to one row per (period_date, variation_code, warehouse_id) and
--    forward-fill the stock level.
--    v1 built per-row deltas then re-accumulated them with a running SUM. That is
--    two window passes to reproduce a number it already had, and it double-counts
--    whenever two source rows land on the same (SKU, warehouse, date).
--    LAST_VALUE(... IGNORE NULLS) does the forward fill directly, in one pass,
--    after aggregation - i.e. over far fewer rows.
-------------------------------------------------------------------------------
,daily_agg AS (
  SELECT
     period_date
    ,variation_code
    ,warehouse_id
    ,MAX(warehouse_name)         AS warehouse_name
    ,MAX(warehouse_country)      AS warehouse_country
    ,MAX(product_name)           AS product_name
    ,MAX(retail_price)           AS retail_price
    ,MAX(order_sources_name)     AS order_sources_name
    ,MAX(sale_channel)           AS sale_channel
    ,MAX(sale_channel_details)   AS sale_channel_details
    ,MAX(order_year)             AS order_year
    ,SUM(sl_nhap_moi_tu_sx)      AS sl_nhap_moi_tu_sx
    ,SUM(sl_nhap_kho)            AS sl_nhap_kho
    ,MAX(stock_level_raw)        AS stock_level_raw   -- NULL only if no stock row that day
    ,SUM(sales_revenue)          AS sales_revenue
    ,SUM(revenue)                AS revenue
    ,SUM(units_sold)             AS units_sold
  FROM src_filtered
  GROUP BY period_date, variation_code, warehouse_id
)

,stock_filled AS (
  SELECT
     a.* EXCEPT (stock_level_raw)
      ,GREATEST(
       IFNULL(
         LAST_VALUE(a.stock_level_raw IGNORE NULLS) OVER (
           PARTITION BY a.variation_code, a.warehouse_id
           ORDER BY a.period_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
         )
         -- no stock row has ever been seen -> fall back to the master on-hand qty
        ,SAFE_CAST(dw.actual_remain_qty AS NUMERIC))
        ,SAFE_CAST(0 AS NUMERIC)
      ,0                                        -- negative on-hand is meaningless
     ) AS sl_ton_kho
     ,dw.country
  FROM daily_agg a
  LEFT JOIN dim_variation_wh dw
    ON a.variation_code = dw.variation_code
   AND a.warehouse_id   = dw.warehouse_id
)

-------------------------------------------------------------------------------
-- 6. Attach the SKU dimension and apply the caller's date window.
--    The window is applied HERE, not earlier: the forward fill above needs full
--    history to know the opening stock level.
-------------------------------------------------------------------------------
,enriched AS (
  SELECT
     s.period_date
    ,s.variation_code
    ,d.product_code
    ,IFNULL(s.product_name, d.product_name)   AS product_name
    ,d.variation_attributes
    ,d.category
    ,d.sub_category
    ,d.collection_bst
    ,IFNULL(s.retail_price, d.retail_price)   AS retail_price
    ,d.product_launch_date
    ,IFNULL(d.is_sale_end, 0)                 AS is_sale_end
    ,IFNULL(DATE_DIFF(CURRENT_DATE(), d.product_launch_date, DAY), 9999) AS product_days_since_launch
    -- Effective denominator for velocity: a SKU launched 10 days ago cannot be
    -- judged over a 90-day window. Never 0 -> no divide-by-zero downstream.
    ,GREATEST(
       LEAST(
         IFNULL(DATE_DIFF(CURRENT_DATE(), d.product_launch_date, DAY) + 1, c.days_range_param)
        ,c.days_range_param
       )
      ,1
     ) AS days_range
    ,s.warehouse_id
    ,s.warehouse_name
    ,s.warehouse_country
    ,s.sl_nhap_moi_tu_sx
    ,s.sl_nhap_kho
    ,s.sl_ton_kho
    ,s.order_sources_name
    ,s.sale_channel
    ,s.sale_channel_details
    ,s.order_year
    ,s.sales_revenue
    ,s.revenue
    ,s.units_sold
  FROM stock_filled s
  CROSS JOIN const c
  LEFT JOIN dim_variation d ON s.variation_code = d.variation_code
  WHERE (i_FromDate IS NULL OR s.period_date >= i_FromDate)
    AND (i_ToDate   IS NULL OR s.period_date <= i_ToDate)
)

-------------------------------------------------------------------------------
-- 7. Grain selection. This is the ONLY place i_type changes the shape of the
--    data. Everything downstream is written once and partitions by grain_key.
--    i_type = 1 collapses warehouses, so stock is summed and warehouse columns
--    are blanked; i_type = 0 keeps the warehouse dimension.
-------------------------------------------------------------------------------
,grain AS (
  SELECT
     period_date
    ,variation_code
    ,IF(i_type = 1, '', warehouse_id)   AS grain_key      -- window partition key
    ,ANY_VALUE(product_code)            AS product_code
    ,ANY_VALUE(product_name)            AS product_name
    ,ANY_VALUE(variation_attributes)    AS variation_attributes
    ,ANY_VALUE(category)                AS category 
    ,ANY_VALUE(sub_category)            AS sub_category 
    ,ANY_VALUE(collection_bst)          AS collection_bst 
    ,ANY_VALUE(product_days_since_launch) AS product_days_since_launch
    ,ANY_VALUE(days_range)              AS days_range
    ,ANY_VALUE(is_sale_end)             AS is_sale_end
    ,MAX(retail_price)                  AS retail_price
    ,IF(i_type = 1, '', ANY_VALUE(warehouse_id))          AS warehouse_id
    ,IF(i_type = 1, '', ANY_VALUE(warehouse_name))        AS warehouse_name
    ,IF(i_type = 1, '', ANY_VALUE(warehouse_country))     AS warehouse_country
    ,IF(i_type = 1, CAST(NULL AS STRING), MAX(order_sources_name))   AS order_sources_name
    ,IF(i_type = 1, CAST(NULL AS STRING), MAX(sale_channel))         AS sale_channel
    ,IF(i_type = 1, CAST(NULL AS STRING), MAX(sale_channel_details)) AS sale_channel_details
    ,IF(i_type = 1, CAST(NULL AS INT64),  MAX(order_year))           AS order_year
    ,SUM(sl_nhap_moi_tu_sx)             AS sl_nhap_moi_tu_sx
    ,SUM(sl_nhap_kho)                   AS sl_nhap_kho
    ,SUM(sl_ton_kho)                    AS sl_ton_kho
    ,SUM(sales_revenue)                 AS sales_revenue
    ,SUM(revenue)                       AS revenue
    ,SUM(units_sold)                    AS units_sold
  FROM enriched
  GROUP BY period_date, variation_code, grain_key
)

-------------------------------------------------------------------------------
-- 8. Segment flags: detect stock-outs and restocks so "days on hand since last
--    restock" and "consecutive days out of stock" can be accumulated.
-------------------------------------------------------------------------------
,flagged AS (
  SELECT
     g.*
    ,g.sl_ton_kho * IFNULL(g.retail_price, 0) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
    ,DATE_DIFF(g.period_date, prev_date, DAY) AS day_gap
    ,IF(g.sl_ton_kho <= 0 AND prev_stock >  0, 1, 0) AS reset_stock_flag   -- went out of stock
    ,IF(g.sl_ton_kho >  0 AND prev_stock <= 0, 1, 0) AS reset_empty_flag   -- came back in stock
  FROM (
    SELECT
       *
      ,LAG(period_date) OVER w AS prev_date
      ,LAG(sl_ton_kho)  OVER w AS prev_stock
    FROM grain
    WINDOW w AS (PARTITION BY variation_code, grain_key ORDER BY period_date)
  ) g
)

,segmented AS (
  SELECT
     *
    ,SUM(reset_stock_flag) OVER w AS seg_id          -- increments on each stock-out
    ,SUM(reset_empty_flag) OVER w AS empty_stock_id  -- increments on each restock
  FROM flagged
  WINDOW w AS (
    PARTITION BY variation_code, grain_key
    ORDER BY period_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )
)

-------------------------------------------------------------------------------
-- 9. Rolling i_days_range sales window.
--
--    The obvious way to write this is
--        SUM(units_sold) OVER (... RANGE BETWEEN i_days_range - 1 PRECEDING ...)
--    but BigQuery requires a window framing expression to be a LITERAL or a query
--    parameter. A table-function argument is neither, so that form fails to
--    compile ("Window framing expression must be a literal or parameter").
--
--    Instead, model each sale as two events on a single stream:
--        +units_sold at period_date            (the sale enters the window)
--        -units_sold at period_date + N days   (the sale leaves the window)
--    A plain cumulative SUM over that stream is exactly the rolling total, because
--        cum(d) = SUM(units where date <= d) - SUM(units where date + N <= d)
--               = cum(d) - cum(d - N)
--    UNBOUNDED PRECEDING needs no offset, so nothing has to be a literal and any
--    value of i_days_range works. One extra pass over a 2x row set, no join
--    explosion, and no dependence on the daily history being dense.
--
--    Tie-break matters: at a date where an expiry and a real sale coincide, the
--    expiry must be applied FIRST, so that a sale made exactly N days ago has
--    already dropped out. ORDER BY event_date, is_real (0 before 1) guarantees it.
-------------------------------------------------------------------------------
,sales_events AS (
  SELECT variation_code, grain_key, period_date AS event_date,
         IFNULL(units_sold, 0) AS w, 1 AS is_real
  FROM grain
  UNION ALL
  SELECT variation_code, grain_key, DATE_ADD(period_date, INTERVAL i_days_range DAY),
         -IFNULL(units_sold, 0), 0
  FROM grain
)

,rolling AS (
  SELECT variation_code, grain_key, period_date, units_sold_day_range
  FROM (
    SELECT
       variation_code
      ,grain_key
      ,event_date AS period_date
      ,is_real
      ,SUM(w) OVER (
         PARTITION BY variation_code, grain_key
         ORDER BY event_date, is_real
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS units_sold_day_range
    FROM sales_events
  )
  WHERE is_real = 1   -- drop the synthetic expiry rows
)

-------------------------------------------------------------------------------
-- 10. Metrics.
--     units_sold_day_range is a TRUE rolling i_days_range window (v1 summed over
--     the stock segment, which could span months). The v1 behaviour is still
--     exposed, renamed to units_sold_since_restock so the two are not confused.
-------------------------------------------------------------------------------
,metrics AS (
  SELECT
     period_date
    ,ROW_NUMBER() OVER w_desc AS sort_desc
    ,IF(ROW_NUMBER() OVER w_desc = 1, 1, 0) AS is_latest
    ,product_code
    ,variation_code
    ,variation_attributes
    ,category
    ,sub_category
    ,collection_bst
    ,product_days_since_launch
    ,days_range
    ,is_sale_end
    ,product_name
    ,retail_price
    ,warehouse_id
    ,warehouse_name
    ,warehouse_country
    ,sl_nhap_moi_tu_sx
    ,sl_nhap_kho
    ,sl_ton_kho
    ,tong_gia_tri_hang_ton_kho_theo_gia_ban
    ,order_sources_name
    ,sale_channel
    ,sale_channel_details
    ,order_year
    -- i_type = 1 reports lifetime-to-date totals; i_type = 0 reports the day.
    ,IF(i_type = 1, SUM(sales_revenue) OVER w_cum, sales_revenue) AS sales_revenue
    ,IF(i_type = 1, SUM(revenue)       OVER w_cum, revenue)       AS revenue
    ,IF(i_type = 1, SUM(units_sold)    OVER w_cum, units_sold)    AS units_sold

    -- Days the SKU has held stock without hitting zero.
    ,IFNULL(SUM(IF(sl_ton_kho = 0, 0, day_gap)) OVER w_seg, 0)   AS ton_kho_running_days
    -- Consecutive days at zero stock (drives the "no stock" exclusion downstream).
    ,IFNULL(SUM(IF(sl_ton_kho = 0, day_gap, 0)) OVER w_empty, 0) AS emty_stock_days

    -- TRUE rolling window over the last i_days_range calendar days (see step 9).
    ,IFNULL(units_sold_day_range, 0)          AS units_sold_day_range
    -- v1-compatible: units sold since the last stock-out.
    ,IFNULL(SUM(units_sold) OVER w_seg,   0)  AS units_sold_since_restock

    ,sl_ton_kho - IFNULL(LAG(sl_ton_kho) OVER w_asc, sl_ton_kho) AS sl_ton_kho_diff
  FROM segmented
  LEFT JOIN rolling USING (variation_code, grain_key, period_date)
  WINDOW
     w_desc  AS (PARTITION BY variation_code, grain_key ORDER BY period_date DESC)
    ,w_asc   AS (PARTITION BY variation_code, grain_key ORDER BY period_date)
    ,w_cum   AS (PARTITION BY variation_code, grain_key ORDER BY period_date
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ,w_seg   AS (PARTITION BY variation_code, grain_key, seg_id ORDER BY period_date
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ,w_empty AS (PARTITION BY variation_code, grain_key, empty_stock_id ORDER BY period_date
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)

-------------------------------------------------------------------------------
-- 11. Output. Single SELECT: i_type = 1 keeps only the latest snapshot row.
--     No ORDER BY - a TVF cannot guarantee ordering to its caller and the sort
--     was being paid for on every invocation. Order in the calling query.
-------------------------------------------------------------------------------
SELECT
   period_date
  ,IF(i_type = 1, 1, sort_desc) AS sort_desc
  ,is_latest
  ,product_code
  ,variation_code
  ,variation_attributes
  ,category
  ,sub_category
  ,collection_bst
  ,product_days_since_launch
  ,days_range
  ,is_sale_end
  ,product_name
  ,retail_price
  ,warehouse_id
  ,warehouse_name
  ,warehouse_country
  ,sl_nhap_moi_tu_sx
  ,sl_nhap_kho
  ,sl_ton_kho
  ,tong_gia_tri_hang_ton_kho_theo_gia_ban
  ,order_sources_name
  ,sale_channel
  ,sale_channel_details
  ,order_year
  ,sales_revenue
  ,revenue
  ,units_sold
  ,ton_kho_running_days
  ,emty_stock_days
  ,units_sold_day_range
  ,units_sold_since_restock
  ,IF(i_type = 1, 0, sl_ton_kho_diff) AS sl_ton_kho_diff
FROM metrics
WHERE i_type = 0
   OR (i_type = 1 AND is_latest = 1);
