CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_meta.stg_ads_reporting_my`
PARTITION BY proc_date
CLUSTER BY date_stop, campaign_id, adset_name, ad_name
OPTIONS (
  require_partition_filter=true) 
AS
SELECT
  DATE(TIMESTAMP_TRUNC(_PARTITIONTIME, DAY)) AS proc_date,
  CAST(date_start AS DATE) AS date_start,
  CAST(date_stop AS DATE) AS date_stop, 
  SAFE_CAST(campaign_id AS BIGNUMERIC) AS campaign_id, 
  campaign_name, 
  adset_name, 
  ad_name, 
  SAFE_CAST(spend AS FLOAT64) AS spend, 
  SAFE_CAST(reach AS INT64) AS reach,
  SAFE_CAST(actions_page_engagement AS FLOAT64) AS page_engagement, 
  SAFE_CAST(actions_onsite_conversion_messaging_conversation_started_7d AS FLOAT64) AS conversion_messaging_conversation_started_7d,
  SAFE_CAST(cost_per_action_type_onsite_conversion_messaging_conversation_started_7d AS FLOAT64) AS cost_conversion_messaging_conversation_started_7d, 
  SAFE_CAST(clicks AS INT64) AS clicks, 
  SAFE_CAST(cpc AS FLOAT64) AS cpc, 
  SAFE_CAST(cpm AS FLOAT64) AS cpm
FROM `marine-cycle-484213-b4.raw_meta.raw_ads_reporting_my` 
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2020-02-15")