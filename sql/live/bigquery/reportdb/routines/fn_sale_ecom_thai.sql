CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_thai(number_year_back INT64)
AS
WITH CTE_SURFOSM_ECOM_TL AS
  (
  SELECT
      IFNULL(o.external_order_id,o.order_number) AS order_id,
      o.inserted_at AS order_date,
      o.status,
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
      'Kho Ecommerce Thailand' AS warehouse_name,
      COUNT(DISTINCT oi.order_number) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(oi.product_sku,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN  oi.product_code END) AS total_products,
      SUM(CASE WHEN LEFT(oi.product_sku,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.effective_qty ELSE 0  END) AS total_units_sold,
      SUM(oi.original_price ) AS sales_revenue_thai,
      SUM(oi.discount_seller) AS item_total_discount,
      SUM(oi.discount_platform) AS discount_platform,
      SUM(oi.original_price) -  SUM(oi.discount_seller) AS revenue_thai,
      SUM(oi.original_price * 800) AS sales_revenue_vn,
      SUM(oi.original_price * 800) -  SUM(oi.discount_seller * 800) AS revenue_vn
    FROM `marine-cycle-484213-b4.surfosm.core_surfosm_order` AS o
    JOIN `marine-cycle-484213-b4.surfosm.core_surfosm_order_item` AS oi
      ON o.order_number = oi.order_number
    WHERE 1=1
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-02-01' and '2026-02-28'
      --AND o.external_order_id = 'REDACTED_EXAMPLE'
      AND status NOT IN ('cancelled','returned')
      AND (UPPER(TRIM(channel)) LIKE '%SHOPEE%' OR UPPER(TRIM(channel)) LIKE '%TIKTOK%' OR UPPER(TRIM(channel)) LIKE '%LAZADA%')
      --AND ( channel NOT LIKE '%Lsoul - Product Request%'
--    OR channel LIKE '%Lsoul - Change size%'
--    OR channel LIKE '%Lsoul - Online%'
--    OR channel LIKE '%Lsoul - Central Ladprao%'
--    OR channel LIKE '%Lsoul - Offline%'
--    OR channel LIKE '%Lsoul - Emsphere%'
--    OR channel LIKE '%Lsoul - Central World%')  
      GROUP BY 1, 2,3,5,7

    --   UNION ALL

    --   SELECT
    --   o.external_order_id,
    --   o.order_number,
    --   o.inserted_at AS order_date,
    --   'cancelled/returned'  AS status,
    --   'Sale Ecommerce Thai' AS order_sources_name,
    --   CASE 
    --     WHEN UPPER(TRIM(channel)) LIKE '%SHOPEE%' THEN 'Shopee'
    --     WHEN UPPER(TRIM(channel)) LIKE '%TIKTOK%' THEN 'Tiktok'
    --     WHEN UPPER(TRIM(channel)) LIKE '%LAZADA%' THEN 'Lazada'
    --     --ELSE UPPER(TRIM(channel))
    --     END AS sale_channel,
    --   'TL Ecommerce' AS channel,
    --   customer_phone_no AS customer_id,
    --   0 AS total_orders,
    --   0 AS total_products,
    --   0 AS total_units_sold,
    --   0 AS sales_revenue,
    --   0 AS discount_platform,
    --   0 AS item_total_discount,
    --   0 AS revenue,
    -- FROM `marine-cycle-484213-b4.surfosm.core_surfosm_order` AS o
    -- JOIN `marine-cycle-484213-b4.surfosm.core_surfosm_order_item` AS oi
    --   ON o.order_number = oi.order_number
    -- WHERE 1=1
    --   AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
    --   AND status IN ('cancelled','returned')
    --   AND channel NOT LIKE '%Lsoul - Product Request%'
    --   GROUP BY 1, 2, 3,6,8

    --   order by 3, 6
  )
  SELECT
  *
  FROM CTE_SURFOSM_ECOM_TL
  WHERE sale_channel IS NOT NULL;
