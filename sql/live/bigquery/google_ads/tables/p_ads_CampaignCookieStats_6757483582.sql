CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignCookieStats_6757483582`
(
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_absolute_top_impression_percentage FLOAT64 OPTIONS(description="The percent of your ad impressions that are shown as the very first ad above the organic search results."),
  metrics_search_budget_lost_absolute_top_impression_share FLOAT64 OPTIONS(description="The number estimating how often your ad wasn't the very first ad above the organic search results due to a low budget. Note: Search budget lost absolute top impression share is reported in the range of 0 to 0.9. Any value above 0.9 is reported as 0.9001."),
  metrics_search_budget_lost_top_impression_share FLOAT64 OPTIONS(description="The number estimating how often your ad didn't show anywhere above the organic search results due to a low budget. Note: Search budget lost top impression share is reported in the range of 0 to 0.9. Any value above 0.9 is reported as 0.9001."),
  metrics_search_rank_lost_absolute_top_impression_share FLOAT64 OPTIONS(description="The number estimating how often your ad wasn't the very first ad above the organic search results due to poor Ad Rank. Note: Search rank lost absolute top impression share is reported in the range of 0 to 0.9. Any value above 0.9 is reported as 0.9001."),
  metrics_search_rank_lost_top_impression_share FLOAT64 OPTIONS(description="The number estimating how often your ad didn't show anywhere above the organic search results due to poor Ad Rank. Note: Search rank lost top impression share is reported in the range of 0 to 0.9. Any value above 0.9 is reported as 0.9001."),
  metrics_search_top_impression_share FLOAT64 OPTIONS(description="The impressions you've received in the top location (anywhere above the organic search results) compared to the estimated number of impressions you were eligible to receive in the top location. Note: Search top impression share is reported in the range of 0.1 to 1. Any value below 0.1 is reported as 0.0999."),
  metrics_top_impression_percentage FLOAT64 OPTIONS(description="The percent of your ad impressions that are shown anywhere above the organic search results."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd.")
)
PARTITION BY DATE(_PARTITIONTIME);
