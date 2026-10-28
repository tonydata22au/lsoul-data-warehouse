CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignConversionStats_6757483582`
(
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_value_per_conversion FLOAT64 OPTIONS(description="The value of conversions divided by the number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_conversion_action STRING OPTIONS(description="Resource name of the conversion action."),
  segments_conversion_action_category STRING OPTIONS(description="Conversion action category."),
  segments_conversion_action_name STRING OPTIONS(description="Conversion action name."),
  segments_conversion_attribution_event_type STRING OPTIONS(description="Conversion attribution event type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_slot STRING OPTIONS(description="Position of the ad."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
