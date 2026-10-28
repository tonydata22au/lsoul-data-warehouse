CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_PaidOrganicStats_4435779462`
(
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  metrics_average_cpc FLOAT64 OPTIONS(description="The total cost of all clicks divided by the total number of clicks received."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_combined_clicks INT64 OPTIONS(description="The number of times your ad or your site's listing in the unpaid results was clicked. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_combined_clicks_per_query FLOAT64 OPTIONS(description="The number of times your ad or your site's listing in the unpaid results was clicked (combined_clicks) divided by combined_queries. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_combined_queries INT64 OPTIONS(description="The number of searches that returned pages from your site in the unpaid results or showed one of your text ads. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_organic_clicks INT64 OPTIONS(description="The number of times someone clicked your site's listing in the unpaid results for a particular query. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_organic_clicks_per_query FLOAT64 OPTIONS(description="The number of times someone clicked your site's listing in the unpaid results (organic_clicks) divided by the total number of searches that returned pages from your site (organic_queries). See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_organic_impressions INT64 OPTIONS(description="The number of listings for your site in the unpaid search results. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_organic_impressions_per_query FLOAT64 OPTIONS(description="The number of times a page from your site was listed in the unpaid search results (organic_impressions) divided by the number of searches returning your site's listing in the unpaid results (organic_queries). See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  metrics_organic_queries INT64 OPTIONS(description="The total number of searches that returned your site's listing in the unpaid results. See the help page at https://support.google.com/google-ads/answer/3097241 for details."),
  paid_organic_search_term_view_search_term STRING OPTIONS(description="The search term."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_search_engine_results_page_type STRING OPTIONS(description="Type of the search engine results page."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
