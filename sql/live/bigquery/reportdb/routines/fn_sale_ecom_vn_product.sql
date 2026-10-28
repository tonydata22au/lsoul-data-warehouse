CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_vn_product(number_year_back INT64)
AS
WITH CTE_ECOM_VN AS 
(
SELECT
      o.order_id,
      order_date,
      oi.product_id,
      p.product_code,
      oi.product_name,
      v.variation_display_id AS variation_code,
      v.variation_attributes,
      p.product_launch_date,
      oi.retail_price,
      CASE WHEN TRIM(UPPER(p.product_tags)) = 'SYS_01_SALE_END' THEN 1 ELSE 0 END is_sale_end,
      oi.cart_quantity AS units_sold,
      oi.sales_revenue, --Doanh so ban hang
      CASE 
        WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` ) 
        THEN 0 
        ELSE item_total_discount 
      END AS item_total_discount,
      ROUND(SAFE_DIVIDE(
                      (
                        CASE 
                          WHEN oi.sales_revenue = 0 THEN 0 
                          ELSE advanced_platform_fee_marketplace_voucher 
                        END
                         -
                        CASE
                          WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` )  or LENGTH(o.order_id) = 5
                         THEN 0  ELSE total_discount 
                         END 
                      )
                      ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                      ),0) AS extra_sale_revenue,
      oi.sales_revenue
      - CASE 
        WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` ) 
        THEN 0 
        ELSE item_total_discount 
        END
      + ROUND(SAFE_DIVIDE(
                      (
                        CASE 
                          WHEN oi.sales_revenue = 0 THEN 0 
                          ELSE advanced_platform_fee_marketplace_voucher 
                        END
                         -
                        CASE
                          WHEN SAFE_CAST(o.order_id AS INT64) IN (SELECT order_id  FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` )  or LENGTH(o.order_id) = 5
                         THEN 0  ELSE total_discount 
                         END 
                      )
                      ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                      ),0) AS revenue,
      order_sources_name,
      'VN Ecommerce' AS sale_channel,
      oi.warehouse_id,
      o.warehouse_name,
      customer_id,
      --status_name,
      --assigning_seller_name,
      --creator_name,
    FROM `marine-cycle-484213-b4.core_pancake.core_order` AS o 
    JOIN    `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.variation_id = v.variation_id
    WHERE 1=1    
      --AND o.order_id = 'REDACTED_EXAMPLE'
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-01-01' and '2026-01-31'
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      AND oi.cart_quantity > 0
      AND o.order_id NOT IN (SELECT order_to_returned_id FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND status_name NOT IN ('canceled','returned','packing','returning')
      AND o.order_sources_name IN ('Tiktok', 'Shopee', 'Lazada')
      AND o.warehouse_name = 'Kho Ecommerce Việt Nam'
      AND LEFT(variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD','TU')
      order by 2 desc, 4, 5
)
SELECT
*
FROM CTE_ECOM_VN
WHERE sales_revenue - item_total_discount + extra_sale_revenue  <> 0;
