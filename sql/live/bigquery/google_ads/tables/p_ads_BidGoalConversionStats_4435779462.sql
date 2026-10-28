CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_BidGoalConversionStats_4435779462`
(
  bidding_strategy_id INT64 OPTIONS(description="The ID of the bidding strategy."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  bidding_strategy_campaign_count INT64 OPTIONS(description="The number of campaigns attached to this bidding strategy. This field is read-only."),
  bidding_strategy_non_removed_campaign_count INT64 OPTIONS(description="The number of non-removed campaigns attached to this bidding strategy. This field is read-only."),
  metrics_all_conversions FLOAT64 OPTIONS(description="The total number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_all_conversions_value FLOAT64 OPTIONS(description="The total value of all conversions."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cross_device_conversions FLOAT64 OPTIONS(description="Conversions from when a customer clicks on a Google Ads ad on one device, then converts on a different device or browser. Cross-device conversions are already included in all_conversions."),
  metrics_value_per_all_conversions FLOAT64 OPTIONS(description="The value of all conversions divided by the number of all conversions."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
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
