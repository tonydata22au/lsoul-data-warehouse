CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_marketing_website_traffic_analysis()
AS
WITH users AS (
  SELECT
    pseudo_user_id,
    DATETIME_TRUNC(TIMESTAMP_MICROS(user_info. user_first_touch_timestamp_micros),DAY) AS first_seen_date,
    row_number() OVER (PARTITION BY pseudo_user_id order by user_info. user_first_touch_timestamp_micros ASC) AS user_return_count
  FROM  `marine-cycle-484213-b4.analytics_529084033.pseudonymous_users_*`
)
,user_tag AS (
  SELECT
    u.pseudo_user_id,
    first_seen_date,
    CASE
      WHEN user_return_count = 1 THEN 'New'
      ELSE 'Returning'
    END AS user_type
  FROM users u
),
event_day AS (
  SELECT 
  e.event_date,
  DATETIME_TRUNC(DATETIME(TIMESTAMP_MICROS(event_timestamp),"Asia/Ho_Chi_Minh"),DAY) AS event_timestamp,
  e.user_pseudo_id,
  geo.city ,
  geo.country,
  geo.region,
  geo.continent,
  device.category AS device_category,
  traffic_source.medium AS traffic_medium,
  traffic_source.source AS traffic_source,
  session_traffic_source_last_click.cross_channel_campaign.default_channel_group AS traffic_type,
  COUNTIF(event_name = 'session_start') AS sessions,
  COUNTIF(event_name = 'page_view') AS page_view,
  COUNTIF(event_name = 'click') AS click,
  COUNTIF(event_name = 'view_search_results') AS view_search_results,
  COUNTIF(event_name = 'first_visit') AS first_visit,
  COUNTIF(event_name = 'scroll') AS scroll,
  COUNTIF(event_name = 'user_engagement') AS user_engagement,
  COUNTIF(event_name = 'form_start') AS form_start,
  COUNTIF(event_name = 'form_submit') AS form_submit
  FROM `marine-cycle-484213-b4.analytics_529084033.events_*` e
  WHERE   is_active_user = TRUE
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11
)
  SELECT
  event_timestamp,
  EXTRACT(MONTH FROM event_timestamp) AS event_month,
  first_seen_date,
  ed.user_pseudo_id,
  ut.user_type,
  sessions,
  page_view,click,view_search_results,first_visit,scroll,user_engagement,form_start,form_submit,
  city,country,region,continent,
  device_category,
  traffic_medium, traffic_source, traffic_type
  FROM event_day ed
  LEFT JOIN user_tag ut ON ed.user_pseudo_id = ut.pseudo_user_id
  ORDER BY 1,2;
