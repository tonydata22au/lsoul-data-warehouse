CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AssetGroupProductGroupStats_4435779462`
(
  asset_group_product_group_view_asset_group STRING OPTIONS(description="The asset group associated with the listing group filter."),
  asset_group_product_group_view_asset_group_listing_group_filter STRING OPTIONS(description="The resource name of the asset group listing group filter."),
  asset_group_product_group_view_resource_name STRING OPTIONS(description="The resource name of the asset group product group view. Asset group product group view resource names have the form: customers/{customer_id}/assetGroupProductGroupViews/{asset_group_id}~{listing_group_filter_id}"),
  metrics_average_cpc FLOAT64 OPTIONS(description="The total cost of all clicks divided by the total number of clicks received."),
  metrics_average_cpm FLOAT64 OPTIONS(description="Average cost-per-thousand impressions (CPM)."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_conversions FLOAT64 OPTIONS(description="The number of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true. If you use conversion-based bidding, your bid strategies will optimize for these conversions."),
  metrics_conversions_from_interactions_rate FLOAT64 OPTIONS(description="Conversions from interactions divided by the number of ad interactions (such as clicks for text ads or views for video ads). This only includes conversion actions which include_in_conversions_metric attribute is set to true. If you use conversion-based bidding, your bid strategies will optimize for these conversions."),
  metrics_conversions_value FLOAT64 OPTIONS(description="The value of conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true. If you use conversion-based bidding, your bid strategies will optimize for these conversions."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_cost_per_conversion FLOAT64 OPTIONS(description="The cost of ad interactions divided by conversions. This only includes conversion actions which include_in_conversions_metric attribute is set to true. If you use conversion-based bidding, your bid strategies will optimize for these conversions."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  segments_ad_network_type STRING OPTIONS(description="Ad network type."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, for example, MONDAY."),
  segments_device STRING OPTIONS(description="Device to which metrics apply."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, for example, the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
