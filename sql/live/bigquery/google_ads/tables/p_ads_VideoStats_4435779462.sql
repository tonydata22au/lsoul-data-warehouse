CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_VideoStats_4435779462`
(
  ad_group_ad_ad_id INT64 OPTIONS(description="The ID of the ad."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  video_channel_id STRING OPTIONS(description="The owner channel id of the video."),
  video_id STRING OPTIONS(description="The ID of the video."),
  ad_group_ad_status STRING OPTIONS(description="The status of the ad."),
  metrics_all_conversions_from_interactions_rate FLOAT64 OPTIONS(description="All conversions from interactions (as oppose to view through conversions) divided by the number of ad interactions."),
  metrics_average_cpm FLOAT64 OPTIONS(description="Average cost-per-thousand impressions (CPM)."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_cost_per_conversion FLOAT64 OPTIONS(description="The cost of ad interactions divided by conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_click_type STRING OPTIONS(description="Click type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
