CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_store_vn(number_year_back INT64)
AS
SELECT
      o.order_id,
      order_date,
      status_name,
      CASE WHEN order_sources_name IN (NULL,'') THEN 'Store' ELSE order_sources_name END AS order_sources_name,
      'VN Offline Store' AS sale_channel,
      CASE
        WHEN o.warehouse_name LIKE 'Kho Nguyễn Trãi' THEN 'Store Nguyễn Trãi'
        WHEN o.warehouse_name LIKE 'POP-UP OFFICE' THEN 'VN Pop-up'
        ELSE o.warehouse_name
      END AS sale_channel_details,
      CASE 
        WHEN tags LIKE '%Facebook%'   THEN 'Facebook'
        WHEN tags LIKE '%Instagram%'  THEN 'Instagram'
        WHEN tags LIKE '%Tiktok%'     THEN 'Tiktok'
        WHEN tags LIKE '%Website%' OR  tags LIKE '%Google%' THEN 'Online Ads'
        WHEN tags LIKE '%Shopee%'     THEN 'Shopee'
        WHEN tags LIKE '%XIAO%'       THEN 'Xiaohongshu'
       ELSE 'N/A'
      END AS customer_from_ads_source,
      oi.warehouse_id,
      oi.warehouse_name,
      customer_id,
      COUNT(DISTINCT oi.order_id) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.product_id END) AS total_products,
      SUM(CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.cart_quantity ELSE 0 END) AS total_units_sold,
      SUM(oi.sales_revenue) AS sales_revenue,
      SUM(oi.item_total_discount) AS item_total_discount,
      SUM(oi.sales_revenue) - SUM(item_total_discount) + advanced_platform_fee_marketplace_voucher - total_discount  AS revenue
      -- advanced_platform_fee_marketplace_voucher,
      -- total_discount,
      -- is_exchange_order,
      -- exchange_value,
      -- assigning_seller_name,
      -- creator_name,
    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    WHERE 1=1
      --AND DATE_TRUNC(o.inserted_at, YEAR) >='2026-01-01' 
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2025-11-01' and '2025-11-30'
      --AND o.order_id = 'REDACTED_EXAMPLE'
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND oi.cart_quantity > 0
      AND o.total_price > 0
      AND status_name NOT IN ('cancelled','returned')
      AND o.order_sources_name NOT LIKE ('Wholesale')
      AND o.order_sources_name IN (null,'') 
      AND is_received_at_shop = 1 
      AND o.warehouse_name IN ('Kho Nguyễn Trãi','POP-UP OFFICE') 
      GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9, 10, advanced_platform_fee_marketplace_voucher, total_discount
      order by 1, 2, 5, 4;
