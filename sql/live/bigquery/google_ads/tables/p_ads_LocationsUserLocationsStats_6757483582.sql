CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_LocationsUserLocationsStats_6757483582`
(
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  user_location_view_country_criterion_id INT64 OPTIONS(description="Criterion Id for the country."),
  campaign_status STRING OPTIONS(description="The status of the campaign. When a new campaign is added, the status defaults to ENABLED."),
  metrics_average_cpc FLOAT64 OPTIONS(description="The total cost of all clicks divided by the total number of clicks received."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_conversions_from_interactions_rate FLOAT64 OPTIONS(description="Conversions from interactions divided by the number of ad interactions (such as clicks for text ads or views for video ads). This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_cost_per_conversion FLOAT64 OPTIONS(description="The cost of ad interactions divided by conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_view_through_conversions INT64 OPTIONS(description="The total number of view-through conversions. These happen when a customer sees an image or rich media ad, then later completes a conversion on your site without interacting with (e.g., clicking on) another ad."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_geo_target_most_specific_location STRING OPTIONS(description="Resource name of the geo target constant that represents the most specific location."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy."),
  user_location_view_targeting_location BOOL OPTIONS(description="Target location.")
)
PARTITION BY DATE(_PARTITIONTIME);
