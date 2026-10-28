CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_website_product`(
  number_year_back INT64 -- number of years back from current year
)
AS 
(
--SALE WEBSITE
-- SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_website_product`(0) ORDER BY 1 DESC
WITH CTE AS (
SELECT
      o.increment_id AS order_id,
      o.created_at AS order_date,
      o.updated_at,
      oi.items_sku AS variation_code,
      oi.items_name AS product_name,
      CASE WHEN o.state <> o.status THEN CONCAT(o.state,'/',o.status) ELSE o.status END AS status,
      'Website' AS order_sources_name,
      'VN Online' AS sale_channel,
      o.store_name AS sale_channel_details,
      billing_address_country_id AS country_code,
      billing_address_city AS city,
      customer_email,
      CASE WHEN customer_is_guest = 1 THEN 'Yes' ELSE 'No' END AS customer_is_guest,
      o.order_currency_code,
      total_amount AS  original_sales_revenue,
      CASE
          WHEN o.order_currency_code = 'USD' THEN total_amount * 26000
          WHEN o.order_currency_code = 'THB' THEN total_amount * 800
          WHEN o.order_currency_code = 'CNY' THEN total_amount * 3800
          ELSE grand_total
        END AS sales_revenue_vn,
      item_discount_amount AS discount_amount,
      amount_refunded,
      qty_ordered AS units_sold,
      qty_canceled,
      qty_refunded, 
      qty_shipped,
      CASE WHEN COUNT(oi.items_sku) OVER (PARTITION BY oi.items_sku, o.increment_id ORDER BY o.increment_id) > 1 AND retail_price_incl_tax IS NULL THEN 1 ELSE 0 END AS remove_duplicate
     
    FROM `marine-cycle-484213-b4.magento.core_magento_order` AS o
    JOIN `marine-cycle-484213-b4.magento.core_magento_order_item` AS oi ON o.entity_id = oi.entity_id
    WHERE 1=1
      AND DATE_TRUNC(o.created_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.created_at, day) between '2025-11-01' and '2025-11-30'
      --AND oi.total_amount > 0
      order by 3 desc, 2 desc
)
SELECT
* EXCEPT (remove_duplicate)
FROM CTE
WHERE remove_duplicate = 0

)


   