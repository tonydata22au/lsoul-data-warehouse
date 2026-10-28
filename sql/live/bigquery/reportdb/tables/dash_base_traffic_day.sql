CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_base_traffic_day`
(
  period_date DATE,
  country STRING,
  level_1 STRING,
  level_2 STRING,
  level_3 STRING,
  traffic_type STRING,
  user_type STRING,
  is_paid_traffic BOOL,
  sessions INT64,
  users INT64,
  page_views INT64,
  clicks INT64,
  scrolls INT64,
  engagements INT64,
  searches INT64,
  first_visits INT64,
  form_starts INT64,
  form_submits INT64,
  is_ga4_history_complete BOOL
)
OPTIONS(
  description="Daily LSOUL website traffic from GA4 via fn_marketing_website_traffic_analysis(), mapped onto the reporting hierarchy. Grain: period_date x country x level_1/2/3 x traffic_type x user_type."
);
