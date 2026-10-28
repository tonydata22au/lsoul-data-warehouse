CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_china_product_inventory(i_type INT64, i_number_year_back INT64)
AS
WITH stock_store_cn AS (
SELECT 
ROW_NUMBER() OVER (PARTITION BY skuCode, warehouse_name, DATE(updated_at) ORDER BY proc_date desc) AS sort_num
,updated_at ,product_code, skuCode, product_name, product_launch_date,variation_attributes 
,warehouse_name
,Kho
,country
,sl_nhap_kho
,realNum AS sl_ton_kho
,retail_price
FROM 
(
  SELECT DISTINCT
  i.proc_date
  ,i.updated_at ,v.product_code, i.skuCode, p.product_name, p.product_launch_date,variation_attributes
  ,'Kho Trung Quốc (Back-up)' AS warehouse_name --Kho TXmall
  ,'TXmall' AS Kho --Kho TXmall
  ,'CHINA' AS country
  ,IFNULL(realNum - LAG(realNum) OVER (PARTITION BY i.skuId, i.warehouse_name ORDER BY i.updated_at),0) AS sl_nhap_kho
  ,i.realNum
  ,v.retail_price
  FROM `marine-cycle-484213-b4.dianplus.core_dianplus_inventory` i
  LEFT JOIN  `marine-cycle-484213-b4.core_pancake.core_product` p ON i.skuCode = p.display_id
  LEFT JOIN   `marine-cycle-484213-b4.core_pancake.core_variations` v ON i.skuCode = v.variation_display_id
  
)
ORDER BY 4,2 DESC
--AND realNum > 0
)

,stock_store_cn_arg AS (
  SELECT
  updated_at ,product_code, skuCode AS variation_code, product_name, product_launch_date,variation_attributes
  ,warehouse_name
  ,Kho
  ,country
  ,retail_price
  ,SUM(sl_nhap_kho) AS sl_nhap_kho
  ,MAX(CASE WHEN sort_num = 1 THEN sl_ton_kho ELSE 0 END) AS sl_ton_kho
  ,MAX(CASE WHEN sort_num = 1 THEN retail_price ELSE retail_price END) * MAX(CASE WHEN sort_num = 1 THEN sl_ton_kho ELSE 0 END) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
  FROM stock_store_cn 
  GROUP BY 1,2,3,4,5,6,7,8,9,10
  ORDER BY 3, 1 DESC
)

,stock_ecom_cn AS (
SELECT 
ROW_NUMBER() OVER (PARTITION BY sku_id,DATE(vn_modified) ORDER BY vn_modified desc) AS sort_num
,vn_modified
,product_code
,sku_id
,product_name
,product_launch_date
,variation_attributes
,warehouse_name
,Kho
,country
,IFNULL(qty - LAG(qty) OVER (PARTITION BY sku_id ORDER BY vn_modified),0) AS sl_nhap_kho
,purchase_qty
,qty AS sl_ton_kho
,retail_price
FROM
(
SELECT DISTINCT
i.vn_modified ,i.product_code, i.sku_id, IFNULL(p.product_name,name) AS product_name , i.product_launch_date,variation_attributes
,'Kho Trung Quốc (Back-up)' AS warehouse_name 
,'Ecommerce TQ' AS Kho --'Kho Ecommerce China'
,'CHINA' AS country
,qty
,purchase_qty
,v.retail_price
FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory` i
LEFT JOIN  `marine-cycle-484213-b4.core_pancake.core_product` p ON i.sku_id = p.display_id
LEFT JOIN   `marine-cycle-484213-b4.core_pancake.core_variations` v ON i.sku_id = v.variation_display_id
WHERE TRIM(i.sku_id) NOT LIKE '001'
)
order by 4,2 desc
)

,stock_ecom_cn_arg AS (
  SELECT
  DATE(vn_modified) AS updated_at
  ,product_code
  ,sku_id AS variation_code
  ,product_name
  ,product_launch_date
  ,variation_attributes
  ,warehouse_name
  ,Kho
  ,country
  ,retail_price
  ,SUM(sl_nhap_kho) AS sl_nhap_kho
  ,MAX(CASE WHEN sort_num = 1 THEN purchase_qty ELSE 0 END) AS purchase_qty
  ,MAX(CASE WHEN sort_num = 1 THEN sl_ton_kho ELSE 0 END) AS sl_ton_kho
  ,MAX(CASE WHEN sort_num = 1 THEN retail_price ELSE retail_price END) * MAX(CASE WHEN sort_num = 1 THEN sl_ton_kho ELSE 0 END) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
  FROM stock_ecom_cn
  GROUP BY 1,2,3,4,5,6,7,8,9,10
  ORDER BY 3, 1 DESC
)

,master_table AS (
SELECT
  updated_at ,product_code, variation_code, product_name, product_launch_date,variation_attributes,Kho,pancake_warehouse_id,warehouse_name,country
  ,retail_price
  ,sl_nhap_kho
  ,sl_ton_kho
  ,tong_gia_tri_hang_ton_kho_theo_gia_ban
  
FROM
  (
  SELECT 
  updated_at ,product_code, variation_code, product_name, product_launch_date,variation_attributes ,Kho,warehouse_name,country
  ,retail_price
  ,sl_nhap_kho
  ,sl_ton_kho
  ,tong_gia_tri_hang_ton_kho_theo_gia_ban
  ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS pancake_warehouse_id --Kho Trung Quốc (Back-up)
  FROM stock_store_cn_arg
  WHERE  DATE_TRUNC(updated_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  AND LEFT(variation_code,2) NOT IN ('TG','HT','HN','HH','TD')

  UNION ALL
   SELECT updated_at ,product_code, variation_code, product_name, product_launch_date,variation_attributes ,Kho,warehouse_name,country
  ,retail_price
  ,sl_nhap_kho
  ,sl_ton_kho
  ,tong_gia_tri_hang_ton_kho_theo_gia_ban
  ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS pancake_warehouse_id --Kho Trung Quốc (Back-up)
  FROM stock_ecom_cn_arg
  WHERE  DATE_TRUNC(updated_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  AND LEFT(variation_code,2) NOT IN ('TG','HT','HN','HH','TD')
  ORDER BY 3,1 DESC
  )
  WHERE DATE(updated_at) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)

SELECT
CASE WHEN ROW_NUMBER() OVER (PARTITION BY variation_code ORDER BY updated_at DESC) = 1 THEN 1 ELSE 0 END AS is_latest
,*
FROM
(
SELECT
updated_at
,product_code
,variation_code
,product_name
,product_launch_date
,variation_attributes
,'' AS Kho
,pancake_warehouse_id
,warehouse_name
,country
,MAX(retail_price) AS retail_price
,SUM(sl_nhap_kho)  AS sl_nhap_kho
,SUM(sl_ton_kho)   AS sl_ton_kho
,MAX(retail_price) * SUM(sl_ton_kho) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
FROM master_table
WHERE i_type = 0

GROUP BY 1,2,3,4,5,6,8,9,10
)

UNION ALL

SELECT
CASE WHEN ROW_NUMBER() OVER (PARTITION BY variation_code, Kho ORDER BY updated_at DESC) = 1 THEN 1 ELSE 0 END AS is_latest
,*
FROM master_table
WHERE i_type = 1;
