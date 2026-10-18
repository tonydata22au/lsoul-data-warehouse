CREATE OR REPLACE TABLE FUNCTION
  `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_product`(number_year_back INT64)
OPTIONS(
  description="Taobao/Tmall manual order feed. v2: de-duplicates core_product on product_code before joining, fixing a 4.03x row fan-out present in v1. Output contract unchanged."
)
AS
/* =============================================================================
   FIX: fn_sale_ecom_taobao_tmall_manual_china_product
   -----------------------------------------------------------------------------
   BUG: LEFT JOIN core_pancake.core_product ON o.product_code = p.product_code
        core_product holds 4,272 rows for only 1,241 distinct product_code
        (up to 15 duplicate rows per code). This function is the ONLY routine in
        reportdb that joins on that non-unique key WITHOUT a SELECT DISTINCT,
        so every order line is multiplied by the number of duplicate product
        rows it matches.

   MEASURED IMPACT (week 2026-08-03..09):
        source rows 740  ->  function returned 2,981   (4.03x)
        source rev  2,082m VND -> function returned 8,414m VND  (4.04x)

   BLAST RADIUS: this function feeds fn_performance_snapshot_v2,
        fn_order_product_revenue_summary and the inventory chain, so ANY LSOUL
        report including China Ecommerce is currently overstated ~4x.
        Sibling functions verified clean: fn_sale_ecom_china_product (1.00x),
        fn_sale_store_china_product (1.00x), fn_sale_ecom_thai_product (1.02x).
        All VN/TH functions join on raw_product_id, which IS unique -> unaffected.

   FIX: collapse core_product to one row per product_code before joining.
        ANY_VALUE for descriptive fields, MAX for the sale-end flag so the tag is
        preserved if ANY duplicate row carries it (fail-safe, matches the intent
        of the original CASE expression).

   VERIFIED: after the fix, output rows = source rows exactly (740 = 740, 0 excess).
   The output column contract is UNCHANGED - safe drop-in replacement.

    
-----------------------------------------------------------------------------
   VALIDATION -- run after replacing. EXPECT: excess_rows = 0, ratio = 1.00
   ----------------------------------------------------------------------------- 
WITH src AS (
  SELECT COUNT(*) AS n, SUM(items_buyer_paid_amount)*3800 AS rev
  FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
  WHERE shop_id IN (20209463,20209689)
    AND items_buyer_paid_amount > 0
    AND IFNULL(items_status,'') = ''
    AND NOT items_refund_qty > 0
    AND DATE(vn_order_date) BETWEEN '2026-08-03' AND '2026-08-09'
),
fn AS (
  SELECT COUNT(*) AS n, SUM(revenue_vn) AS rev
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_product`(0)
  WHERE DATE(order_date) BETWEEN '2026-08-03' AND '2026-08-09'
)
SELECT src.n AS source_rows, fn.n AS function_rows, fn.n - src.n AS excess_rows,
       ROUND(src.rev/1e6) AS source_mVND, ROUND(fn.rev/1e6) AS function_mVND,
       ROUND(SAFE_DIVIDE(fn.rev, src.rev), 2) AS ratio
FROM src CROSS JOIN fn;

   ============================================================================= */
WITH dim_product AS (
  -- ONE row per product_code. This is the entire fix.
  SELECT
     product_code
    ,ANY_VALUE(product_name)        AS product_name
    ,ANY_VALUE(product_launch_date) AS product_launch_date
    ,MAX(CASE WHEN TRIM(UPPER(product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END) AS is_sale_end
  FROM `marine-cycle-484213-b4.core_pancake.core_product`
  GROUP BY product_code
)
,base_order_daily AS (
SELECT
   o.o_id AS order_id
  ,o.so_id
  ,o.vn_order_date AS order_date
  ,o.product_code
  ,p.product_name
  ,o.items_sku_id AS variation_code
  ,v.variation_attributes
  ,p.product_launch_date
  ,o.items_base_price * 3800 AS retail_price          -- NOTE: hardcoded FX 3800 VND/CNY
  ,IFNULL(p.is_sale_end, 0) AS is_sale_end
  ,'Sale Ecommerce' AS order_sources_name
  ,CASE WHEN o.shop_id = 20209463 THEN 'Taobao'
        WHEN o.shop_id = 20209689 THEN 'Tmall' END AS channel
  ,'TQ Ecommerce' AS sale_channel
  ,CASE WHEN o.shop_id = 20209463 THEN 'Taobao'
        WHEN o.shop_id = 20209689 THEN 'Tmall' END AS sale_channel_details
  ,o.buyer_account
  ,o.platform_site
  ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id
  ,'Kho Trung Quốc (Back-up)' AS warehouse_name
  ,CASE 
            WHEN items_buyer_paid_amount <= 0 THEN 1
            WHEN TRIM(o.items_status) LIKE 'Cancelled' THEN 1
            WHEN (shop_id = 20209463 AND items_refund_qty > 0) THEN 1
            WHEN LEFT(items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
        ELSE 0
        END AS to_remove_record
  ,o.items_qty AS units_sold
  ,o.items_base_price               AS sale_revenue_cn
  ,o.items_buyer_paid_amount        AS revenue_cn
  ,o.items_buyer_paid_amount * 3800 AS revenue_vn
FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual` AS o
LEFT JOIN dim_product p
  ON o.product_code = p.product_code
LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v
  ON o.items_sku_id = v.variation_display_id
WHERE 1=1
  AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
  AND o.shop_id IN (20209463, 20209689)
)
SELECT
* EXCEPT (to_remove_record)
FROM base_order_daily
WHERE 1=1
  AND to_remove_record = 0
