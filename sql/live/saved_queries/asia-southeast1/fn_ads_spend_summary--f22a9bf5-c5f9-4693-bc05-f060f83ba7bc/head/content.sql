CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_ads_spend_summary`(
  i_number_year_back INT64
) 
AS (
/*
Author: Toan Pham
Date: 10/06/2026

TESTING: SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_ads_spend_summary`(0) 

*/

WITH META_ADS AS (
SELECT 
day 
,'META' AS ads_channel
,CASE 
  WHEN UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%' THEN 'THAILAND'
  WHEN UPPER(campaign_name) LIKE '%HAN-QUOC%' OR UPPER(campaign_name) LIKE '%HÀN%' THEN 'HAN QUOC'
  ELSE 'VIETNAM'
  END ads_target_country
,CASE 
  WHEN spent_source = 'SPENT STORE' THEN 'Store' 
  WHEN spent_source = 'SPENT SOCIAL' THEN 'Sale Online'
  WHEN spent_source = 'SPENT ECOMMERCE' THEN 'Sale Ecommerce'
  ELSE spent_source
  END ads_target_order_sources_name
,CASE 
  WHEN 
        spent_source IN ('SPENT SOCIAL','SPENT ECOMMERCE')
        AND (UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%')
  THEN 'TL Ecommerce'
  WHEN  spent_source IN ('SPENT SOCIAL')
        AND NOT (UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%')
  THEN 'VN Online'
  WHEN  spent_source IN ('SPENT STORE')
        AND NOT (
                  (UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%')
                AND (UPPER(campaign_name) LIKE '%HAN-QUOC%' OR UPPER(campaign_name) LIKE '%HÀN%')
                )
  THEN 'VN Offline Store'
  WHEN  spent_source IN ('SPENT ECOMMERCE')
        AND NOT (
                  (UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%')
                AND (UPPER(campaign_name) LIKE '%HAN-QUOC%' OR UPPER(campaign_name) LIKE '%HÀN%')
                )
  THEN 'VN Ecommerce'  
  ELSE 'VN Offline Store'
  END ads_target_sale_channel
,CASE
    WHEN campaign_type LIKE '%FB%' THEN 'Facebook'
    WHEN campaign_type LIKE '%IG%' THEN 'Instagram'
    WHEN TRIM(UPPER(campaign_type)) LIKE '%WEB%' THEN 'Website'
    WHEN IFNULL(campaign_type,'') NOT LIKE '' THEN 'Store Nguyễn Trãi'
  END ads_target_sale_channel_details
,CASE
    WHEN campaign_type LIKE '%FB%' THEN 'Facebook'
    WHEN campaign_type LIKE '%IG%' THEN 'Instagram'
    WHEN TRIM(UPPER(campaign_type)) LIKE '%WEB%' THEN 'Facebook'
    WHEN IFNULL(campaign_type,'') NOT LIKE '' THEN 'Facebook'
  END customer_from_ads_source
,amount_spend
,reach
,clicks
,cpc
,cpm
,page_engagement
,conversion_messaging_conversation_started_7d
,cost_conversion_messaging_conversation_started_7d
,CASE WHEN campaign_type IS NULL THEN 0 ELSE 1 END AS is_ads_sale_campaign
FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_a` 
WHERE DATE_TRUNC(day, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)

UNION ALL
SELECT 
day
,'META' AS ads_channel
,'US'AS ads_target_country 
,'Sale Online' AS ads_target_order_sources_name 
,'VN Online' AS ads_target_sale_channel
,CASE
    WHEN campaign_type LIKE '%FB%' THEN 'Facebook'
    WHEN campaign_type LIKE '%IG%' THEN 'Instagram'
    ELSE 'Website' 
  END ads_target_sale_channel_details
,CASE
    WHEN campaign_type LIKE '%FB%' THEN 'Facebook'
    WHEN campaign_type LIKE '%IG%' THEN 'Instagram'
    ELSE 'Facebook'
  END customer_from_ads_source
,amount_spend
,reach
,clicks
,cpc
,cpm
,page_engagement
,conversion_messaging_conversation_started_7d
,cost_conversion_messaging_conversation_started_7d
,CASE WHEN campaign_type IS NULL THEN 0 ELSE 1 END AS is_ads_sale_campaign
FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_my` 
WHERE DATE_TRUNC(day, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
ORDER BY 1 DESC
)

--TIKTOK
,TIKTOK_ADS AS (

--TIKTOK VN
SELECT 
inserted_at AS day
,'TIKTOK' AS ads_channel
,CASE 
  WHEN country_code = 'VN' THEN 'VIETNAM'
  WHEN country_code = 'TH' THEN 'THAILAND'
  WHEN country_code = 'US' THEN 'US'
  ELSE country_code
  END AS ads_target_country
,
CASE 
  WHEN country_code = 'VN' THEN 'Store'
  WHEN country_code = 'TH' THEN 'Store'
  WHEN country_code = 'US' THEN 'Sale Online'
  ELSE 'Sale Ecommerce' 
  END AS ads_target_order_sources_name
,CASE
  WHEN country_code = 'VN' THEN 'VN Offline Store'
  WHEN country_code = 'TH' THEN 'TL Offline Store'
  WHEN country_code = 'US' THEN 'VN Online'
  ELSE 'VN Ecommerce'
  END AS ads_target_sale_channel
,CASE
  WHEN country_code = 'VN' THEN 'Store Nguyễn Trãi'
  WHEN country_code = 'TH' THEN 'Emsphere'
  WHEN country_code = 'US' THEN 'Website'
  ELSE 'Tiktok'
  END AS ads_target_sale_channel_details
,'Tiktok' AS customer_from_ads_source
,spend AS amount_spend
,reach
,clicks
,cpc
,cpm
,engaged_view_15s
,0 AS live_views
,0 AS `10_second_live_views`
,0 AS live_follows
,0 AS cost_per_live_view 
 FROM `marine-cycle-484213-b4.core_tiktok.core_reporting_basic_auction_ad` 
 WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)

UNION ALL

SELECT  
inserted_at AS day
,'TIKTOK' AS ads_channel
,'VIETNAM' AS ads_target_country
,'Sale Ecommerce' AS ads_target_order_sources_name
,'VN Ecommerce' AS ads_target_sale_channel
,'Tiktok Vietnam' AS ads_target_sale_channel_details
,'Tiktok' AS customer_from_ads_source
,cost AS amount_spend
,0 AS reach
,0 AS clicks
,0 AS cpc
,0 AS cpm
,0 AS engaged_view_15s
,live_views
,`10_second_live_views`
,live_follows
,cost_per_live_view 
FROM `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report` 
WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)

UNION ALL

--TIKTOK THAI LAND
SELECT 
inserted_at AS day
,'TIKTOK' AS ads_channel
,CASE 
  WHEN country_code = 'VN' THEN 'VIETNAM'
  WHEN country_code = 'TH' THEN 'THAILAND'
  WHEN country_code = 'US' THEN 'US'
  ELSE country_code
  END AS ads_target_country
,'Sale Ecommerce' AS ads_target_order_sources_name
,'TL Ecommerce' AS ads_target_sale_channel
,'Tiktok Thailand' AS ads_target_sale_channel_details
,'Tiktok' AS customer_from_ads_source
,spend * 800 AS amount_spend
,reach 
,clicks
,cpc * 800
,cpm * 800
,engaged_view_15s
,0 AS live_views
,0 AS `10_second_live_views`
,0 AS live_follows
,0 AS cost_per_live_view 
 FROM `marine-cycle-484213-b4.core_tiktok.core_thai_reporting_basic_auction_ad` 
 WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)

UNION ALL

SELECT  
inserted_at AS day
,'TIKTOK' AS ads_channel
,'THAILAND' AS ads_target_country
,'Sale Ecommerce' AS ads_target_order_sources_name
,'TL Ecommerce' AS ads_target_sale_channel
,'Tiktok Thailand' AS ads_target_sale_channel_details
,'Tiktok' AS customer_from_ads_source
,cost * 800 AS amount_spend
,0 AS reach
,0 AS clicks
,0 AS cpc
,0 AS cpm
,0 AS engaged_view_15s
,live_views
,`10_second_live_views`
,live_follows
,cost_per_live_view 
FROM `marine-cycle-484213-b4.core_tiktok.core_tiktok_thai_gmv_max_report` 
WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
ORDER BY 1 desc

)

,ggads AS (
  SELECT
  day
  ,'Google Ads' AS ads_channel
  ,CASE 
      WHEN account_id = '6757483582' THEN 'US'
      ELSE 'VIETNAM'
    END AS  ads_target_country
  ,CASE 
      WHEN account_id = '6757483582' THEN 'Sale Online'
      ELSE 'Store' 
    END AS ads_target_order_sources_name
  ,CASE 
      WHEN account_id = '6757483582' THEN 'VN Online' 
      ELSE 'VN Offline Store'
    END AS ads_target_sale_channel
  ,CASE 
      WHEN account_id = '6757483582' THEN 'Website' 
      ELSE 'Store Nguyễn Trãi' 
    END AS ads_target_sale_channel_details
  ,'Online Ads' AS customer_from_ads_source
  ,total_spend AS amount_spend
  ,total_impressions
  ,total_clicks
  ,cpc
  ,cost_per_conversion
  FROM `marine-cycle-484213-b4.reportdb.fn_ads_spend_ggads`(i_number_year_back)
)

,base_ads_summary AS (
SELECT
    day
    ,ads_channel
    ,ads_target_order_sources_name
    ,ads_target_sale_channel
    ,ads_target_sale_channel_details
    ,customer_from_ads_source
    ,SUM(amount_spend) AS amount_spend
    ,SUM(reach) AS reach
    ,SUM(clicks) AS clicks
    ,AVG(cpc) AS cpc
    ,AVG(cpm) AS cpm
    ,SUM(engaged_view_15s) AS engaged_view_15s
    ,SUM(live_views) AS live_views
    ,SUM(`10_second_live_views`) AS `10_second_live_views`
    ,SUM(live_follows) AS live_follows
    ,SUM(cost_per_live_view) AS  cost_per_live_view
FROM
(
    --META
    SELECT
    day
    ,ads_channel
    ,ads_target_country
    ,ads_target_order_sources_name
    ,ads_target_sale_channel
    ,ads_target_sale_channel_details
    ,customer_from_ads_source
    ,amount_spend
    ,reach
    ,clicks
    ,cpc
    ,cpm
    ,0 AS engaged_view_15s
    ,0 AS live_views
    ,0 AS `10_second_live_views`
    ,0 AS live_follows
    ,0 AS cost_per_live_view 
    FROM META_ADS
    WHERE is_ads_sale_campaign = 1
  
    UNION ALL
    
    --TIKTOK
    SELECT
    day
     day
    ,ads_channel
    ,ads_target_country
    ,ads_target_order_sources_name
    ,ads_target_sale_channel
    ,ads_target_sale_channel_details
    ,customer_from_ads_source
    ,amount_spend
    ,reach
    ,clicks
    ,cpc
    ,cpm
    ,engaged_view_15s
    ,live_views
    ,`10_second_live_views`
    ,live_follows
    ,cost_per_live_view 
    FROM TIKTOK_ADS

    UNION ALL

    --Google Ads
    SELECT
     day
    ,ads_channel
    ,ads_target_country
    ,ads_target_order_sources_name
    ,ads_target_sale_channel
    ,ads_target_sale_channel_details
    ,customer_from_ads_source
    ,amount_spend
    ,total_impressions
    ,total_clicks
    ,cpc
    ,cost_per_conversion
    ,0 AS engaged_view_15s
    ,0 AS live_views
    ,0 AS `10_second_live_views`
    ,0 AS live_follows
    ,0 AS cost_per_live_view 
    FROM ggads

) T
GROUP BY 1,2,3,4,5,6
ORDER BY 1 DESC
)

,order_ads AS (
SELECT 
    COALESCE(DATETIME(day),period_date) AS period_date
    ,COALESCE(ads_channel,'N/A') AS ads_channel
    ,COALESCE(ads_target_order_sources_name,order_sources_name) AS ads_target_order_sources_name
    ,COALESCE(ads_target_sale_channel,sale_channel) AS ads_target_sale_channel
    ,COALESCE(ads_target_sale_channel_details,sale_channel_details) AS ads_target_sale_channel_details
    ,IFNULL(o.customer_from_ads_source,'N/A') AS order_customer_from_ads_source
    ,IFNULL(amount_spend,0) AS amount_spend
    ,IFNULL(reach,0) AS reach
    ,IFNULL(clicks,0) AS clicks
    ,IFNULL(cpc,0) AS cpc
    ,IFNULL(cpm,0) AS cpm
    ,IFNULL(engaged_view_15s,0) AS engaged_view_15s
    ,IFNULL(live_views,0) AS live_views
    ,IFNULL(`10_second_live_views`,0) AS `10_second_live_views`
    ,IFNULL(live_follows,0) AS live_follows
    ,IFNULL(cost_per_live_view,0) AS cost_per_live_view
    ,IFNULL(sales_revenue,0) AS sales_revenue
    ,IFNULL(revenue,0) AS revenue
    ,IFNULL(total_units_sold,0) AS total_units_sold
    ,IFNULL(total_orders,0) AS total_orders
    ,IFNULL(total_customers,0) AS total_customers

FROM base_ads_summary ads 
FULL OUTER JOIN `marine-cycle-484213-b4.reportdb.fn_order_revenue_summary`(1,i_number_year_back,1) o
    ON ads.day = DATE(period_date)
    AND ads_target_order_sources_name = order_sources_name
    AND ads_target_sale_channel = sale_channel
    AND (ads_target_sale_channel_details = sale_channel_details OR ads.customer_from_ads_source = o.customer_from_ads_source)
    AND o.country <> 'CHINA'
)

SELECT
    period_date
    ,ads_channel
    ,ads_target_order_sources_name
    ,ads_target_sale_channel
    ,ads_target_sale_channel_details
    ,order_customer_from_ads_source
    ,SUM(amount_spend) AS amount_spend
    ,SUM(reach) AS reach
    ,SUM(clicks) AS clicks
    ,SUM(cpc) AS cpc
    ,SUM(cpm) AS cpm
    ,SUM(engaged_view_15s) AS engaged_view_15s
    ,SUM(live_views) AS live_views
    ,SUM(`10_second_live_views`) AS `10_second_live_views`
    ,SUM(live_follows) AS live_follows
    ,SUM(cost_per_live_view) AS  cost_per_live_view
    ,SUM(sales_revenue) AS sales_revenue
    ,SUM(revenue) AS revenue
    ,SUM(total_units_sold) AS total_units_sold
    ,SUM(total_orders) AS total_orders
    ,SUM(total_customers) AS total_customers
FROM order_ads
GROUP BY 1,2,3,4,5,6
ORDER BY 1 DESC

);