CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_order_revenue_summary(i_type INT64, i_number_year_back INT64, i_remove_non_sale_data INT64)
AS
WITH base_daily AS (
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store'  AS order_sources_name, sale_channel , warehouse_name, 'VIETNAM' AS country
    ,sale_channel_details,revenue, sales_revenue, total_units_sold, total_orders, total_products,customer_id, customer_from_ads_source FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Online' AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
    ,order_sources_name AS sale_channel_details,revenue, sales_revenue, total_units_sold, total_orders, total_products,customer_id, 'Online Ads' AS customer_from_ads_source FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'VIETNAM' AS country
     ,order_sources_name,revenue, sales_revenue, total_units_sold, total_orders, total_products,customer_id, order_sources_name AS customer_from_ads_source FROM  `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store' AS order_sources_name, sale_channel, warehouse_name, 'THAILAND' AS country
     ,sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue, total_units_sold, total_orders, total_products,customer_id,customer_from_ads_source FROM  `marine-cycle-484213-b4.reportdb.fn_sale_store_thai`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'THAILAND' AS country
    ,channel AS sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue , total_units_sold, total_orders, total_products,customer_id, channel AS customer_from_ads_source from `marine-cycle-484213-b4.reportdb.fn_sale_ecom_thai`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Store' AS order_sources_name, sale_channel, warehouse_name, 'CHINA' AS country
    ,'Store TXmall' AS sale_channel_details,revenue_vn AS revenue, sales_revenue_vn AS sales_revenue, total_units_sold, total_orders, total_products, vipMobilePhone AS customer_id, 'Xiaohongshu' AS customer_from_ads_source FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'CHINA' AS country
    ,sale_channel_details, revenue_vn AS revenue, revenue_vn AS sales_revenue, total_units_sold, total_orders, total_products, CAST(buyer_id AS STRING) AS customer_id, sale_channel_details AS customer_from_ads_source  FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china`(i_number_year_back)
    UNION ALL
    SELECT EXTRACT(YEAR FROM order_date) AS  order_year, order_date, 'Sale Ecommerce' AS order_sources_name, sale_channel, warehouse_name, 'CHINA' AS country
    ,sale_channel_details, revenue_vn AS revenue, revenue_vn AS sales_revenue, total_units_sold, total_orders, total_products, CAST(buyer_account AS STRING) AS customer_id, sale_channel_details AS customer_from_ads_source  FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_taobao_tmall_manual_china`(i_number_year_back)
  )
  
,daily AS (
    SELECT
      IFNULL(day_start,spl.sale_date) AS period_date,
      IFNULL(order_day,spl.day_of_month) AS x_axis,
      IFNULL(order_sources_name,sale_channel_type) AS order_sources_name,
      IFNULL(sale_channel,channel) AS sale_channel,
      NULL AS sale_channel_details,
      NULL AS customer_from_ads_source,
      IFNULL(order_year,EXTRACT(YEAR FROM spl.sale_month_date)) AS order_year,
      IFNULL(country,spl.sale_country) AS country,
      sales_revenue,
      revenue,
      total_units_sold,
      total_orders,
      total_products,
      total_customers,
      metric_value_daily AS target_revenue,
      CASE WHEN t.day_start IS NOT NULL THEN 1 ELSE 0 END AS is_remove_non_sale_data
    FROM 
    ( 
      SELECT
      DATE_TRUNC(order_date,DAY) AS day_start,
      EXTRACT(DAY FROM order_date) AS order_day,
      order_year,
      order_sources_name,
      sale_channel,
      country,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(total_units_sold) AS total_units_sold,
      SUM(total_orders) AS total_orders,
      SUM(total_products) AS total_products,
      COUNT(distinct customer_id) AS total_customers
      FROM base_daily
      GROUP BY 1, 2, 3, 4,5 ,6
    ) t
    FULL OUTER JOIN  `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily` spl ON  spl.sale_date = t.day_start  AND spl.sale_channel_type =  t.order_sources_name AND spl.sale_country = t.country 
    WHERE 1=1
    AND is_for_daily_report = 1
    AND i_type = 0

    UNION ALL

    SELECT
      day_start AS period_date,
      order_day AS x_axis,
      order_sources_name,
      sale_channel,
      sale_channel_details,
      customer_from_ads_source,
      order_year,
      country,
      sales_revenue,
      revenue,
      total_units_sold,
      total_orders,
      total_products,
      total_customers,
      0 AS target_revenue,
      1 AS is_remove_non_sale_data
    FROM 
    ( 
      SELECT
      DATE_TRUNC(order_date,DAY) AS day_start,
      EXTRACT(DAY FROM order_date) AS order_day,
      order_year,
      order_sources_name,
      sale_channel,
      sale_channel_details,
      customer_from_ads_source,
      country,
      SUM(sales_revenue) AS sales_revenue,
      SUM(revenue) AS revenue,
      SUM(total_units_sold) AS total_units_sold,
      SUM(total_orders) AS total_orders,
      SUM(total_products) AS total_products,
      COUNT(distinct customer_id) AS total_customers
      FROM base_daily
      GROUP BY 1, 2, 3, 4,5 ,6,7,8
    ) t
    WHERE 1=1
    AND i_type = 1
  )

  SELECT * FROM daily WHERE i_remove_non_sale_data = 0 OR  (i_remove_non_sale_data = 1 AND is_remove_non_sale_data = 1);
