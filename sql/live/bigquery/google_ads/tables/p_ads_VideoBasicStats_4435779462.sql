CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_VideoBasicStats_4435779462`
(
  ad_group_ad_ad_id INT64 OPTIONS(description="The ID of the ad."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  video_channel_id STRING OPTIONS(description="The owner channel id of the video."),
  video_id STRING OPTIONS(description="The ID of the video."),
  ad_group_ad_status STRING OPTIONS(description="The status of the ad."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_device STRING OPTIONS(description="Device to which metrics apply.")
)
PARTITION BY DATE(_PARTITIONTIME);
