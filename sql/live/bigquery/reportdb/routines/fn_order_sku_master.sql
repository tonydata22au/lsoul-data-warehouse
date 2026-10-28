CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_sku_master(i_number_year_back INT64, i_type INT64)
AS
WITH raw AS (
  SELECT order_date,'VIETNAM' AS country,level_1,'VN Offline Store' AS level_2,level_3, variation_code, total_units_sold,sales_revenue,revenue,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Online',level_3, variation_code, total_units_sold,sales_revenue,revenue,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Ecommerce',level_3, variation_code, total_units_sold,sales_revenue,revenue,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Wholesales',level_3, variation_code, total_units_sold,sales_revenue,revenue,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_wholeshale_vn_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'THAILAND',level_1,'TL Offline Store',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_thai_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'THAILAND',level_1,'VN Online',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'THAILAND',level_1,'TL Ecommerce',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_thai_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Offline Store',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(i_number_year_back,1)
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Ecommerce',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,order_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_v2`(i_number_year_back,1) 
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Ecommerce',level_3, variation_code, total_units_sold,sales_revenue_vn ,revenue_vn,CAST(order_id AS STRING)
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_v2`(i_number_year_back,1)
)
,stage AS (
  SELECT DATE(order_date) AS period_date, * EXCEPT(order_date)
  FROM raw
)
SELECT 
period_date, 
country,
level_1,
level_2,
level_3, 
variation_code, 
SUM(total_units_sold) AS units_sold,
SUM(sales_revenue) AS sales_revenue_vn,
SUM(revenue) AS revenue_vn,
COUNT(distinct order_id) AS total_orders
FROM stage
WHERE i_type = 0
GROUP BY period_date, country,level_1,level_2,level_3, variation_code


UNION ALL

--i_type = 1
SELECT period_date, country,level_1,'' level_2, '' level_3, variation_code,
SUM(total_units_sold),
SUM(sales_revenue),
SUM(revenue),
COUNT(distinct order_id)
FROM stage
WHERE i_type = 1
GROUP BY period_date, country,level_1, variation_code


UNION ALL

--i_type = 2
SELECT period_date, country,'' level_1,level_2, '' level_3, variation_code,
SUM(total_units_sold),
SUM(sales_revenue),
SUM(revenue),
COUNT(distinct order_id)
FROM stage
WHERE i_type = 2
GROUP BY period_date, country,level_2, variation_code

UNION ALL

--i_type = 4
SELECT SAFE_CAST(NULL AS DATE) period_date, '' country,'' level_1,'' level_2, '' level_3, variation_code,
SUM(total_units_sold),
SUM(sales_revenue),
SUM(revenue),
COUNT(distinct order_id)
FROM stage
WHERE i_type = 4
GROUP BY variation_code;
