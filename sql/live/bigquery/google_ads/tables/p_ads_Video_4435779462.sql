CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Video_4435779462`
(
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  video_id STRING OPTIONS(description="The ID of the video."),
  ad_group_ad_status STRING OPTIONS(description="The status of the ad."),
  video_duration_millis INT64 OPTIONS(description="The duration of the video in milliseconds."),
  video_title STRING OPTIONS(description="The title of the video.")
)
PARTITION BY DATE(_PARTITIONTIME);
