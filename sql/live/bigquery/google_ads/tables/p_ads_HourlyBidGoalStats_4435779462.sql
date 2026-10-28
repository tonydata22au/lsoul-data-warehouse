CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_HourlyBidGoalStats_4435779462`
(
  bidding_strategy_id INT64 OPTIONS(description="The ID of the bidding strategy."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  bidding_strategy_campaign_count INT64 OPTIONS(description="The number of campaigns attached to this bidding strategy. This field is read-only."),
  bidding_strategy_non_removed_campaign_count INT64 OPTIONS(description="The number of non-removed campaigns attached to this bidding strategy. This field is read-only."),
  metrics_average_cpc FLOAT64 OPTIONS(description="The total cost of all clicks divided by the total number of clicks received."),
  metrics_average_cpm FLOAT64 OPTIONS(description="Average cost-per-thousand impressions (CPM)."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_from_interactions_rate FLOAT64 OPTIONS(description="Conversions from interactions divided by the number of ad interactions (such as clicks for text ads or views for video ads). This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The total value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_cost_per_conversion FLOAT64 OPTIONS(description="The cost of ad interactions divided by conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_value_per_conversion FLOAT64 OPTIONS(description="The value of conversions divided by the number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_hour INT64 OPTIONS(description="Hour of day as a number between 0 and 23, inclusive."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
