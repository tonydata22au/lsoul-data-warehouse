CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_thailand_product_inventory(i_type INT64, i_number_year_back INT64)
AS
WITH CTE AS (
SELECT DISTINCT
parameter_date
,sku
,p.product_code
,p.product_name
,p.product_tags
,v.retail_price
,'878504e9-fb75-4870-8504-b2ecdbc097ba' AS warehouse_id --Kho Thái (Back-up)
,'Kho Thái Lan' AS warehouse_name
,'THAILAND' AS country
,stock_on_hand
,stock_normal
--,stock_defect, stock_quarantine, stock_expired, stock_shelf_life_hold, stock_pending_destruction

FROM `marine-cycle-484213-b4.surfosm.core_surfosm_inventory` i
LEFT JOIN  `marine-cycle-484213-b4.core_pancake.core_product` p ON i.sku = p.display_id
LEFT JOIN   `marine-cycle-484213-b4.core_pancake.core_variations` v ON i.sku = v.variation_display_id
)

,master AS (
SELECT 
ROW_NUMBER() OVER (PARTITION BY sku ORDER BY parameter_date desc) AS sort_num
,parameter_date AS updated_at
,sku
,product_code
,product_name
,product_tags
,retail_price
,warehouse_id
,warehouse_name 
,country
,IFNULL(stock_on_hand - LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY parameter_date),0) AS sl_nhap_kho
,stock_on_hand
,stock_normal
FROM CTE
WHERE DATE_TRUNC(parameter_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
)

SELECT * FROM master WHERE i_type = 0
union all
SELECT * FROM master WHERE i_type = 1 AND sort_num = 1
ORDER BY 3,1;
