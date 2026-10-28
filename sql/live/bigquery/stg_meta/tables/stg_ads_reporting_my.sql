CREATE TABLE `marine-cycle-484213-b4.stg_meta.stg_ads_reporting_my`
(
  proc_date DATE,
  date_start DATE,
  date_stop DATE,
  campaign_id BIGNUMERIC,
  campaign_name STRING,
  adset_name STRING,
  ad_name STRING,
  spend FLOAT64,
  reach INT64,
  page_engagement FLOAT64,
  conversion_messaging_conversation_started_7d FLOAT64,
  cost_conversion_messaging_conversation_started_7d FLOAT64,
  clicks INT64,
  cpc FLOAT64,
  cpm FLOAT64
)
PARTITION BY proc_date
CLUSTER BY date_stop, campaign_id, adset_name, ad_name
OPTIONS(
  require_partition_filter=true
);
