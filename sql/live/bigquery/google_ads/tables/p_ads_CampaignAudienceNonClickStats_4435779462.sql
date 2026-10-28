CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignAudienceNonClickStats_4435779462`
(
  campaign_criterion_criterion_id STRING OPTIONS(description="Output only. The ID of the criterion. This field is ignored during mutate."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_average_cpe FLOAT64 OPTIONS(description="The average amount that you've been charged for an ad engagement. This amount is the total cost of all ad engagements divided by the total number of ad engagements."),
  metrics_engagement_rate FLOAT64 OPTIONS(description="How often people engage with your ad after it's shown to them. This is the number of ad expansions divided by the number of times your ad is shown."),
  metrics_engagements INT64 OPTIONS(description="The number of engagements. An engagement occurs when a viewer expands your Lightbox ad. Also, in the future, other ad types may support engagement metrics."),
  metrics_trueview_average_cpv FLOAT64 OPTIONS(description="The average amount you pay each time someone views your ad. The average CPV is defined by the total cost of all ad views divided by the number of TrueView views."),
  metrics_video_trueview_view_rate FLOAT64 OPTIONS(description="The number of TrueView views your video ad receives divided by its number of impressions, including thumbnail impressions for TrueView in-display ads."),
  metrics_video_trueview_views INT64 OPTIONS(description="The number of TrueView views your video ads received."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
