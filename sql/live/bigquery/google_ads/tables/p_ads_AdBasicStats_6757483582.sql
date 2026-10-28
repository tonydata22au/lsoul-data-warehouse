CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdBasicStats_6757483582`
(
  ad_group_ad_ad_id INT64 OPTIONS(description="The ID of the ad."),
  ad_group_id INT64 OPTIONS(description="Output only. The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_ad_ad_group STRING OPTIONS(description="The ad group to which the ad belongs."),
  ad_group_base_ad_group STRING OPTIONS(description="For draft or experiment ad groups, this field is the resource name of the base ad group from which this ad group was created. If a draft or experiment ad group does not have a base ad group, then this field is null. For base ad groups, this field equals the ad group resource name. This field is read-only."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_interaction_event_types STRING OPTIONS(description="The types of payable and free interactions."),
  metrics_interactions INT64 OPTIONS(description="The number of interactions. An interaction is the main user action associated with an ad format-clicks for text and shopping ads, views for video ads, and so on."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_slot STRING OPTIONS(description="Position of the ad.")
)
PARTITION BY DATE(_PARTITIONTIME);
