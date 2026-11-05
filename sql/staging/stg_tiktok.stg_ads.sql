--DROP TABLE `marine-cycle-484213-b4.stg_tiktok.stg_ads`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_tiktok.stg_ads`
AS
SELECT
DATE(TIMESTAMP_TRUNC(_PARTITIONTIME, DAY)) AS proc_date,
DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', create_time))  AS create_time,
DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', modify_time))  AS modify_time,
ad_id,
ad_name,
operation_status,
secondary_status,
app_name,
advertiser_id,
campaign_id,
campaign_name,
adgroup_id,
adgroup_name,
display_name,
optimization_event,
ad_format,
creative_type,
ad_text,
tiktok_item_id,
identity_type,
campaign_automation_type
FROM `marine-cycle-484213-b4.raw_tiktok.raw_tiktok_ads`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-01-01")


