CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_sku_warehouse_master(i_number_year_back INT64, i_type INT64)
AS
WITH raw AS (
  SELECT order_date,'VIETNAM' AS country,level_1,'VN Offline Store' AS level_2,level_3, variation_code, 
  product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue,revenue,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Online',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue,revenue,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Ecommerce',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue,revenue,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'VIETNAM',level_1,'VN Wholesales',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue,revenue,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_wholeshale_vn_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'THAILAND',level_1,'TL Offline Store',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_thai_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'THAILAND',level_1,'VN Online',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'THAILAND',level_1,'TL Ecommerce',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_thai_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Offline Store',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(i_number_year_back,3)
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Ecommerce',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,order_id,customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_v2`(i_number_year_back,3) 
  UNION ALL SELECT order_date,'CHINA',level_1,'TQ Ecommerce',level_3, variation_code,
    product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold,sales_revenue_vn ,revenue_vn,CAST(order_id AS STRING),customer_id
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_v2`(i_number_year_back,3)
)
,stage AS (
  SELECT DATE(order_date) AS period_date, * EXCEPT(order_date)
  FROM raw
)

SELECT period_date,'' AS order_id, '' AS customer_id, country,level_1,level_2,level_3, variation_code, product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,
SUM(total_units_sold) AS units_sold,
SUM(sales_revenue) AS sales_revenue_vn,
SUM(revenue) AS revenue_vn,
COUNT(distinct order_id) AS total_orders
FROM stage
WHERE i_type = 0
GROUP BY period_date, country,level_1,level_2,level_3,variation_code,product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold

UNION ALL

SELECT period_date, order_id, customer_id, country,level_1,level_2,level_3, variation_code, product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,
SUM(total_units_sold) AS units_sold,
SUM(sales_revenue) AS sales_revenue_vn,
SUM(revenue) AS revenue_vn,
COUNT(distinct order_id) AS total_orders
FROM stage
WHERE i_type = 1
GROUP BY period_date, order_id, customer_id, country,level_1,level_2,level_3,variation_code,product_code,product_name,variation_attributes, warehouse_id,warehouse_name,retail_price,total_units_sold;
