CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_vn(number_year_back INT64)
AS
WITH CTE_ECOM_VN AS 
(
SELECT
      o.order_id,
      order_date,
      status_name,
      order_sources_name,
      'VN Ecommerce' AS sale_channel,
      oi.warehouse_id,
      o.warehouse_name,
      customer_id,
      COUNT(DISTINCT oi.order_id) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.product_id END) AS total_products,
      SUM(CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.cart_quantity ELSE 0 END) AS total_units_sold,
      SUM(oi.sales_revenue) AS sales_revenue, --Doanh so ban hang
      SUM(oi.item_total_discount) AS item_total_discount,
      SUM(oi.sales_revenue) 
      - CASE 
          WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` ) 
          THEN 0 
          ELSE SUM(CASE WHEN oi.cart_quantity > 0 THEN item_total_discount ELSE 0 END) 
          END
      + CASE 
          WHEN SUM(oi.sales_revenue) = 0 
          THEN 0 
          ELSE advanced_platform_fee_marketplace_voucher 
          END
      - CASE 
          WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` )  or LENGTH(o.order_id) = 5 
          THEN 0  
          ELSE total_discount 
          END AS revenue,
    
      --advanced_platform_fee_marketplace_voucher,
      --total_discount,
      --is_exchange_order,
     -- exchange_value,
      --status_name,
      --assigning_seller_name,
      --creator_name,
    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    WHERE 1=1    
      --AND o.order_id = 'REDACTED_EXAMPLE'
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-01-01' and '2026-01-31'
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      AND o.order_id NOT IN (SELECT order_to_returned_id FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)

      AND status_name NOT IN ('canceled','returned','packing','returning')
      AND o.order_sources_name IN ('Tiktok', 'Shopee', 'Lazada')
      AND o.warehouse_name = 'Kho Ecommerce Việt Nam'
      GROUP BY 1, 2, 3, 4, 6, 7,8,advanced_platform_fee_marketplace_voucher,total_discount
      order by 2 DESC ,4, 5
)
SELECT
*
FROM CTE_ECOM_VN
WHERE total_units_sold > 0 OR revenue <> 0;
