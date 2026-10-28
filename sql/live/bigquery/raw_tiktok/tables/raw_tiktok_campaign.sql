CREATE TABLE `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_campaign`
(
  create_time STRING,
  advertiser_id STRING,
  campaign_id STRING,
  campaign_name STRING,
  operation_status STRING,
  secondary_status STRING,
  budget STRING,
  budget_mode STRING,
  campaign_type STRING,
  campaign_automation_type STRING,
  objective STRING,
  objective_type STRING,
  is_search_campaign STRING,
  is_new_structure STRING,
  is_smart_performance_campaign STRING,
  modify_time STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
