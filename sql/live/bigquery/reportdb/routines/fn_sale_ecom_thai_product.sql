CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_thai_product(number_year_back INT64)
AS
WITH CTE_SURFOSM_ECOM_TL AS
  (
  SELECT DISTINCT
      IFNULL(o.external_order_id,o.order_number) AS order_id,
      o.inserted_at AS order_date,
      oi.product_code,
      IFNULL(p.product_name,oi.product_name) AS product_name,
      oi.product_sku AS variation_code,
      v.variation_attributes,
      oi.product_launch_date,
      original_price * 800 AS retail_price,
      CASE WHEN TRIM(UPPER(p.product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END is_sale_end,
      'Sale Ecommerce' AS order_sources_name,
      CASE 
        WHEN UPPER(TRIM(channel)) LIKE '%SHOPEE%' THEN 'Shopee'
        WHEN UPPER(TRIM(channel)) LIKE '%TIKTOK%' THEN 'Tiktok'
        WHEN UPPER(TRIM(channel)) LIKE '%LAZADA%' THEN 'Lazada'
        --ELSE UPPER(TRIM(channel))
        END AS channel,
      'TL Ecommerce' AS sale_channel,
      customer_phone_no AS customer_id,
      '878504e9-fb75-4870-8504-b2ecdbc097ba' AS warehouse_id,
      'Kho Thái (Back-up)' AS warehouse_name,
      oi.effective_qty AS units_sold,
      oi.original_price AS sales_revenue_thai,
      oi.discount_seller AS item_total_discount,
      oi.discount_platform  AS discount_platform,
      oi.original_price -  oi.discount_seller AS revenue_thai,
      oi.original_price * 800 AS sales_revenue_vn,
      oi.original_price * 800 -  oi.discount_seller * 800 AS revenue_vn
    FROM `marine-cycle-484213-b4.surfosm.core_surfosm_order` AS o
    JOIN `marine-cycle-484213-b4.surfosm.core_surfosm_order_item` AS oi ON o.order_number = oi.order_number
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.product_sku = v.variation_display_id
    WHERE 1=1
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-02-01' and '2026-02-28'
      --AND o.external_order_id = 'REDACTED_EXAMPLE'
      AND status NOT IN ('cancelled','returned')
      AND (UPPER(TRIM(channel)) LIKE '%SHOPEE%' OR UPPER(TRIM(channel)) LIKE '%TIKTOK%' OR UPPER(TRIM(channel)) LIKE '%LAZADA%')
      AND LEFT(oi.product_sku,2) NOT IN ('TG','HT','HN','HH','TD','TU') 
      --AND ( channel LIKE '%Lsoul - Change size%'
--    OR channel LIKE '%Lsoul - Online%'
--    OR channel LIKE '%Lsoul - Central Ladprao%'
--    OR channel LIKE '%Lsoul - Offline%'
--    OR channel LIKE '%Lsoul - Emsphere%'
--    OR channel LIKE '%Lsoul - Central World%')  
   
  )
  SELECT
  *
  FROM CTE_SURFOSM_ECOM_TL
  WHERE sale_channel IS NOT NULL;
