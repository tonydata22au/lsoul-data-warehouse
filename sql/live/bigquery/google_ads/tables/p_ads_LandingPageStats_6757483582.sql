CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_LandingPageStats_6757483582`
(
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_name STRING OPTIONS(description="The name of the ad group. This field is required and should not be empty when creating new ad groups. It must contain fewer than 255 UTF-8 full-width characters. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters."),
  ad_group_status STRING OPTIONS(description="The status of the ad group."),
  campaign_name STRING OPTIONS(description="The name of the campaign. This field is required and should not be empty when creating new campaigns. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters."),
  landing_page_view_unexpanded_final_url STRING OPTIONS(description="The advertiser-specified final URL."),
  metrics_average_cpc FLOAT64 OPTIONS(description="The total cost of all clicks divided by the total number of clicks received."),
  metrics_clicks INT64 OPTIONS(description="The number of clicks."),
  metrics_cost_micros INT64 OPTIONS(description="The sum of your cost-per-click (CPC) and cost-per-thousand impressions (CPM) costs during this period."),
  metrics_ctr FLOAT64 OPTIONS(description="The number of clicks your ad receives (Clicks) divided by the number of times your ad is shown (Impressions)."),
  metrics_impressions INT64 OPTIONS(description="Count of how often your ad has appeared on a search results page or website on the Google Network."),
  metrics_mobile_friendly_clicks_percentage FLOAT64 OPTIONS(description="The percentage of mobile clicks that go to a mobile-friendly page."),
  metrics_speed_score INT64 OPTIONS(description="A measure of how quickly your page loads after clicks on your mobile ads. The score is a range from 1 to 10, 10 being the fastest."),
  metrics_valid_accelerated_mobile_pages_clicks_percentage FLOAT64 OPTIONS(description="The percentage of ad clicks to Accelerated Mobile Pages (AMP) landing pages that reach a valid AMP page."),
  segments_date DATE OPTIONS(description="Date to which metrics apply. yyyy-MM-dd format, e.g., 2018-04-17."),
  segments_day_of_week STRING OPTIONS(description="Day of the week, e.g., MONDAY."),
  segments_month DATE OPTIONS(description="Month as represented by the date of the first day of a month. Formatted as yyyy-MM-dd."),
  segments_quarter DATE OPTIONS(description="Quarter as represented by the date of the first day of a quarter. Uses the calendar year for quarters, e.g., the second quarter of 2018 starts on 2018-04-01. Formatted as yyyy-MM-dd."),
  segments_week DATE OPTIONS(description="Week as defined as Monday through Sunday, and represented by the date of Monday. Formatted as yyyy-MM-dd."),
  segments_year INT64 OPTIONS(description="Year, formatted as yyyy.")
)
PARTITION BY DATE(_PARTITIONTIME);
