CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroupAudienceConversionStats_6757483582`
(
  ad_group_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored for mutates."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_base_ad_group STRING OPTIONS(description="For draft or experiment ad groups, this field is the resource name of the base ad group from which this ad group was created. If a draft or experiment ad group does not have a base ad group, then this field is null. For base ad groups, this field equals the ad group resource name. This field is read-only."),
  ad_group_campaign STRING OPTIONS(description="The campaign to which the ad group belongs."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_all_conversions FLOAT64 OPTIONS(description="The total number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_all_conversions_value FLOAT64 OPTIONS(description="The total value of all conversions."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cross_device_conversions FLOAT64 OPTIONS(description="Conversions from when a customer clicks on a Google Ads ad on one device, then converts on a different device or browser. Cross-device conversions are already included in all_conversions."),
  metrics_value_per_all_conversions FLOAT64 OPTIONS(description="The value of all conversions divided by the number of all conversions."),
  metrics_value_per_conversion FLOAT64 OPTIONS(description="The value of conversions divided by the number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_conversion_action STRING OPTIONS(description="Resource name of the conversion action."),
  segments_conversion_action_category STRING OPTIONS(description="Conversion action category."),
  segments_conversion_action_name STRING OPTIONS(description="Conversion action name."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
