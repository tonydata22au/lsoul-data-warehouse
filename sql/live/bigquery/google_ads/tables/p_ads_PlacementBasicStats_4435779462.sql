CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_PlacementBasicStats_4435779462`
(
  ad_group_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored for mutates."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_base_ad_group STRING OPTIONS(description="For draft or experiment ad groups, this field is the resource name of the base ad group from which this ad group was created. If a draft or experiment ad group does not have a base ad group, then this field is null. For base ad groups, this field equals the ad group resource name. This field is read-only."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_active_view_impressions INT64 OPTIONS(description="A measurement of how often your ad has become viewable on a Display Network site."),
  metrics_active_view_measurability FLOAT64 OPTIONS(description="The ratio of impressions that could be measured by Active View over the number of served impressions."),
  metrics_active_view_measurable_cost_micros INT64 OPTIONS(description="The cost of the impressions you received that were measurable by Active View."),
  metrics_active_view_measurable_impressions INT64 OPTIONS(description="The number of times your ads are appearing on placements in positions where they can be seen."),
  metrics_active_view_viewability FLOAT64 OPTIONS(description="The percentage of time when your ad appeared on an Active View enabled site (measurable impressions) and was viewable (viewable impressions)."),
  metrics_all_conversions FLOAT64 OPTIONS(description="The total number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_all_conversions_value FLOAT64 OPTIONS(description="The total value of all conversions."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_cross_device_conversions FLOAT64 OPTIONS(description="Conversions from when a customer clicks on a Google Ads ad on one device, then converts on a different device or browser. Cross-device conversions are already included in all_conversions."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_interaction_event_types STRING OPTIONS(description="The types of payable and free interactions."),
  metrics_interactions INT64 OPTIONS(description="The number of interactions. An interaction is the main user action associated with an ad format-clicks for text and shopping ads, views for video ads, and so on."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_device STRING OPTIONS(description="Device to which metrics apply.")
)
PARTITION BY DATE(_PARTITIONTIME);
