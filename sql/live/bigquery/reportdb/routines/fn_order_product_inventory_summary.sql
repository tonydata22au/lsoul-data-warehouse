CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_product_inventory_summary(i_type INT64, i_number_year_back INT64, i_country STRING, i_order_sources_name STRING)
AS
WITH calendar_date_to_yesterday AS (
SELECT d AS calendar_date
FROM UNNEST(GENERATE_DATE_ARRAY(
  DATE_SUB(
    DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL 0 + 1 YEAR)
    ,DATE_SUB(DATE_TRUNC(CURRENT_DATE(), DAY),INTERVAL 1 DAY))
    ) AS d
)

,variation_master_table AS (
SELECT
v.updated_at
,v.product_code
,v.variation_display_id
,p.product_name
,p.product_launch_date
,v.retail_price
,vw.warehouse_id
,vw.actual_remain_qty
FROM `marine-cycle-484213-b4.core_pancake.core_variations` v
JOIN `marine-cycle-484213-b4.core_pancake.core_product` p ON v.product_id = p.raw_product_id
JOIN `marine-cycle-484213-b4.core_pancake.core_variation_warehouses` vw ON v.variation_id = vw.variation_id 
WHERE 1=1
AND LEFT(v.variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD','TU')
AND vw.warehouse_id NOT LIKE ''
ORDER BY 3, 1 DESC
)


,product_inventory_warehouse_daily AS (
SELECT
DATE(IFNULL(i.inserted_at,v.updated_at)) AS inserted_at
,v.product_code
,v.variation_display_id 
,v.product_name
,v.product_launch_date
,v.retail_price
,v.warehouse_id
,i.warehouse_name
  ,IFNULL(sl_nhap_moi_tu_sx,0) AS sl_nhap_moi_tu_sx
  ,IFNULL(sl_nhap_kho,0) AS sl_nhap_kho
  ,IFNULL(sl_ton_kho,v.actual_remain_qty) AS sl_ton_kho
  ,IFNULL(tong_gia_tri_hang_ton_kho_theo_gia_ban,v.retail_price * v.actual_remain_qty) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
FROM variation_master_table v
LEFT JOIN `marine-cycle-484213-b4.reportdb.fn_product_variations_warehouse_summary`(1,0,'') i ON v.variation_display_id = i.variation_code AND v.warehouse_id = i.warehouse_id
WHERE 1=1
--AND v.variation_display_id = 'A24122789-3'

UNION ALL

SELECT
o.updated_at
,o.product_code
,o.variation_code 
,o.product_name
,o.product_launch_date
,o.retail_price
,o.pancake_warehouse_id
,o.warehouse_name
,0 AS sl_nhap_moi_tu_sx
,o.sl_nhap_kho
,o.sl_ton_kho
,o.tong_gia_tri_hang_ton_kho_theo_gia_ban
FROM `marine-cycle-484213-b4.reportdb.fn_china_product_inventory`(1,'') o 

ORDER BY  1 asc
)

,product_order_ecom_thai_china AS (
SELECT
o.period_date
,o.product_code
,o.variation_code
,o.warehouse_id
  ,units_sold
  ,sales_revenue
  ,revenue
  ,order_sources_name
  ,sale_channel
  ,sale_channel_details
FROM `marine-cycle-484213-b4.reportdb.fn_order_product_revenue_summary`(0,0,'','') o
LEFT JOIN variation_master_table v ON v.variation_display_id = o.variation_code AND v.warehouse_id = o.warehouse_id
WHERE 1=1
AND v.variation_display_id is null
)

SELECT
d.calendar_date
,i.product_code
,i.variation_display_id
,i.product_name
,i.product_launch_date
,i.retail_price
,i.warehouse_id
,i.sl_nhap_moi_tu_sx
,i.sl_nhap_kho
,i.sl_ton_kho
,i.tong_gia_tri_hang_ton_kho_theo_gia_ban
 
FROM calendar_date_to_yesterday d
LEFT JOIN product_inventory_warehouse_daily i ON DATE(i.inserted_at) = d.calendar_date

ORDER BY 1 ASC;
