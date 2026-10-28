CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_master(i_number_year_back INT64, i_type INT64)
AS
WITH raw AS (
     SELECT

    --VIETNAM 
    order_date, 
    'VIETNAM' AS country, 
    'Store' AS level_1, 
    level_2, 
    level_3,
    CAST(order_id AS STRING) AS order_id,
    sales_revenue, 
    revenue, 
    total_units_sold AS units_sold, 
    CAST(customer_id AS STRING) AS customer_id,
    customer_from_ads_source 
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn_v2`(i_number_year_back,0)

    UNION ALL
    SELECT order_date, 'VIETNAM', 'Sale Online',level_2, level_3,
    CAST(order_id AS STRING),sales_revenue,revenue,total_units_sold,customer_id, 'Online Ads' 
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(i_number_year_back,0)

    UNION ALL
    SELECT order_date, 'VIETNAM', 'Sale Ecommerce',level_2, level_3
    ,CAST(order_id AS STRING),sales_revenue,revenue, total_units_sold,customer_id,level_3 
    FROM  `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn_v2`(i_number_year_back,0)

    UNION ALL
    SELECT order_date, 'VIETNAM', 'Wholesales', level_2, level_3
    ,CAST(order_id AS STRING),sales_revenue,revenue, total_units_sold,customer_id,customer_from_ads_source
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_wholeshale_vn_v2`(i_number_year_back,0)

    --THAILAND
    UNION ALL
    SELECT order_date,'THAILAND','Store',level_2, level_3
    ,CAST(order_id AS STRING), sales_revenue_vn,revenue_vn, total_units_sold,customer_id, customer_from_ads_source 
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_thai_v2`(i_number_year_back,0)
    
    UNION ALL
    SELECT order_date,'THAILAND','Sale Ecommerce',level_2,level_3
    ,CAST(order_id AS STRING),sales_revenue_vn,revenue_vn, total_units_sold,customer_id,level_3
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_thai_v2`(i_number_year_back,0)

    UNION ALL
    SELECT  order_date,'THAILAND', 'Sale Online',level_2,level_3
    ,CAST(order_id AS STRING),sales_revenue_vn,revenue_vn, total_units_sold,customer_id,level_3
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(i_number_year_back,0)

    --CHINA
    UNION ALL
    SELECT order_date,'CHINA','Store',level_2,'Store TXmall'
    ,CAST(order_id AS STRING), sales_revenue_vn,revenue_vn, total_units_sold,customer_id, 'Xiaohongshu' FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(i_number_year_back,0)

    UNION ALL
    SELECT order_date,'CHINA','Sale Ecommerce',level_2,level_3
    ,CAST(order_id AS STRING),sales_revenue_vn, revenue_vn, total_units_sold,customer_id,level_3
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_v2`(i_number_year_back,0)
    
    UNION ALL
    SELECT order_date,'CHINA','Sale Ecommerce',level_2,level_3
    ,CAST(order_id AS STRING),sales_revenue_vn, revenue_vn, total_units_sold,customer_id,level_3 
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china_v2`(i_number_year_back,0)
  )
 
,stage AS (
  SELECT order_date, country, level_1, level_2, level_3, order_id, customer_id,
         SUM(sales_revenue) AS sales_revenue,   -- true GMV not recoverable; equal by construction
         SUM(revenue) AS revenue,
         SUM(units_sold) AS units_sold,
  FROM raw
  GROUP BY 1,2,3,4,5,6,7
  --WHERE country <> 'CHINA' and level_1 <> 'Sale Ecommerce'
)

  SELECT * FROM stage;
