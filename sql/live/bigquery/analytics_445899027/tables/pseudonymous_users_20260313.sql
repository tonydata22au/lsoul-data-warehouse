CREATE TABLE `marine-cycle-484213-b4.analytics_445899027.pseudonymous_users_20260313`
(
  pseudo_user_id STRING,
  stream_id STRING,
  user_info STRUCT<last_active_timestamp_micros INT64, user_first_touch_timestamp_micros INT64, first_purchase_date STRING>,
  device STRUCT<operating_system STRING, category STRING, mobile_brand_name STRING, mobile_model_name STRING, unified_screen_name STRING>,
  geo STRUCT<city STRING, country STRING, continent STRING, region STRING>,
  audiences ARRAY<STRUCT<id INT64, name STRING, membership_start_timestamp_micros INT64, membership_expiry_timestamp_micros INT64, npa BOOL>>,
  user_properties ARRAY<STRUCT<key STRING, value STRUCT<string_value STRING, set_timestamp_micros INT64, user_property_name STRING>>>,
  user_ltv STRUCT<revenue_in_usd FLOAT64, sessions INT64, engagement_time_millis INT64, purchases INT64, engaged_sessions INT64, session_duration_micros INT64>,
  predictions STRUCT<in_app_purchase_score_7d FLOAT64, purchase_score_7d FLOAT64, churn_score_7d FLOAT64, revenue_28d_in_usd FLOAT64>,
  privacy_info STRUCT<is_limited_ad_tracking STRING, is_ads_personalization_allowed STRING>,
  occurrence_date STRING,
  last_updated_date STRING
);
