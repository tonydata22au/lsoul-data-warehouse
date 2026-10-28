--drop table `marine-cycle-484213-b4.core_meta.core_ads_reporting_a` 
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_meta.core_ads_reporting_a`
PARTITION BY day
CLUSTER BY campaign_id, adset_name, ad_name
OPTIONS (
  require_partition_filter=false) 
AS
SELECT DISTINCT
  date_start AS day,
  campaign_id, 
  campaign_name, 
  adset_name, 
  ad_name, 
  spend AS amount_spend, 
  reach,
  page_engagement, 
  conversion_messaging_conversation_started_7d,
  ROUND(cost_conversion_messaging_conversation_started_7d,1) AS cost_conversion_messaging_conversation_started_7d, 
  clicks, 
  ROUND(cpc,1) AS cpc, 
  ROUND(cpm,1) AS cpm, 
  UPPER(REGEXP_EXTRACT(campaign_name, r'^([^_]+_[^_]+)_')) AS campaign_type,
  CASE
  WHEN LEFT(campaign_name, STRPOS(campaign_name || '_', '_') - 1) IN ('Eng', 'Reach') THEN 'SPENT STORE'
  WHEN SUBSTR(LEFT(campaign_name, STRPOS(campaign_name || '_', '_') - 1), 1, 4) = 'Mess' THEN 'SPENT SOCIAL'
  WHEN UPPER(REGEXP_EXTRACT(campaign_name, r'^[^_]+_([^_]+)_')) = 'TIKTOK' THEN 'SPENT ECOMMERCE'
  ELSE 'OTHER'
  END AS spent_source

FROM `marine-cycle-484213-b4.stg_meta.stg_ads_reporting_a` 
WHERE proc_date >= "2020-02-15";