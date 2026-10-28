CREATE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_thai_ads`
(
  create_time STRING,
  ad_id STRING,
  ad_name STRING,
  operation_status STRING,
  secondary_status STRING,
  app_name STRING,
  advertiser_id STRING,
  campaign_id STRING,
  campaign_name STRING,
  adgroup_id STRING,
  adgroup_name STRING,
  display_name STRING,
  optimization_event STRING,
  ad_format STRING,
  creative_type STRING,
  ad_text STRING,
  tiktok_item_id STRING,
  identity_id STRING,
  identity_type STRING,
  is_aco STRING,
  campaign_automation_type STRING,
  modify_time STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
