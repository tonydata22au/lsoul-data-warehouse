CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_product_revenue_summary(i_type INT64, i_number_year_back INT64, i_country STRING, i_order_sources_name STRING)
AS
WITH base_daily AS (
   SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store'  AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
   ,sale_channel_details,revenue, sales_revenue, units_sold, customer_id, product_code,product_name,variation_code,variation_attributes, warehouse_id,retail_price
   FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn_product`(i_number_year_back)
  UNION ALL
  SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Online' AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
   ,order_sources_name AS sale_channel_details,revenue, sales_revenue, units_sold, customer_id, product_code,product_name,variation_code,variation_attributes, warehouse_id,retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
    ,order_sources_name AS sale_channel_details,revenue, sales_revenue, units_sold, customer_id, product_code,product_name,variation_code,variation_attributes, warehouse_id,retail_price
    FROM  `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Wholesales' AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
    ,order_sources_name AS sale_channel_details,revenue, sales_revenue, units_sold, customer_id, product_code,product_name,variation_code,variation_attributes, warehouse_id,retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_wholeshale_vn_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store' AS order_sources_name, sale_channel, warehouse_name, 'THAILAND' AS country
    ,sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue, units_sold, customer_id, product_code,product_name,variation_code,variation_attributes, warehouse_id, retail_price
    FROM  `marine-cycle-484213-b4.reportdb.fn_sale_store_thai_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Online' AS order_sources_name, sale_channel, warehouse_name, 'THAILAND' AS country
    ,'Website' AS sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue ,units_sold, customer_id, product_code ,product_name, variation_code,variation_attributes, warehouse_id,retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'THAILAND' AS country
    ,channel AS sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue ,units_sold, customer_id, product_code ,product_name, variation_code,variation_attributes, warehouse_id,retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_thai_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store' AS order_sources_name, sale_channel, warehouse_name, 'CHINA' AS country
    ,'Store TXmall' AS sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue, units_sold, vipMobilePhone AS customer_id, product_code ,product_name, variation_code,variation_attributes, warehouse_id, retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_product`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'CHINA' AS country
    ,sale_channel_details, revenue_vn AS revenue, revenue_vn AS sales_revenue, units_sold, CAST(buyer_id AS STRING) AS customer_id, product_code ,product_name, variation_code,variation_attributes, warehouse_id, retail_price
    FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_product`(i_number_year_back)

)
--,daily AS (
    SELECT
      day_start AS period_date,
      order_day AS x_axis,
      product_code,
      product_name,
      variation_code,
      TRIM(CONCAT(product_name, ' ' ,variation_attributes)) AS variation_attributes,
      retail_price,
      order_sources_name,
      sale_channel,
      sale_channel_details,
      order_year,
      country,
      warehouse_id,
      warehouse_name,
      sales_revenue,
      revenue,
      units_sold,
      customers
    FROM 
    ( 
      SELECT
      DATE_TRUNC(order_date,DAY) AS day_start,
      EXTRACT(DAY FROM order_date) AS order_day,
      order_year,
      product_code,
      product_name,
      variation_code,
      variation_attributes,
      retail_price,
      order_sources_name,
      sale_channel,
      sale_channel_details,
      country,
      warehouse_id,
      warehouse_name,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(units_sold) AS units_sold,
      COUNT(distinct customer_id) AS customers
      FROM base_daily
      GROUP BY 1, 2, 3, 4,5 ,6,7,8,9,10,11,12,13,14
    ) t
    WHERE 1=1
    AND (i_country = '' OR country = i_country)
    AND (i_order_sources_name = '' OR order_sources_name = i_order_sources_name)
    ORDER BY 5,6,1 DESC;
