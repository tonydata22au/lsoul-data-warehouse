CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_ads_metrics_daily(i_number_year_back INT64)
OPTIONS(
  description="Daily ads-platform metrics across Meta, TikTok and Google Ads. Grain: day x ads_channel x ads_account x market x campaign_name. Every metric column from every source feed is preserved; NULL means the platform does not report it. Spend exposed as spend_native (+currency_code, fx_to_vnd) and spend_vnd. All rates recomputed from components at output grain - never AVG-then-SUM. Meta reports no impressions column, so impressions are derived as spend/cpm*1000 and flagged with impressions_is_derived. No order-revenue join, so spend always reconciles to the platforms.")
AS
WITH
meta_vn AS (
  SELECT
    day,
    'META' AS ads_channel,
    'Meta - LSOUL VN' AS ads_account,
    CASE
      WHEN UPPER(campaign_name) LIKE '%THAI%' OR UPPER(campaign_name) LIKE '%THÁI%' THEN 'THAILAND'
      WHEN UPPER(campaign_name) LIKE '%HAN-QUOC%' OR UPPER(campaign_name) LIKE '%HÀN%' THEN 'HAN QUOC'
      ELSE 'VIETNAM'
    END AS market,
    'core_meta.core_ads_reporting_a' AS source_feed,
    campaign_name,
    campaign_type,
    spent_source,
    'VND' AS currency_code,
    CAST(1 AS NUMERIC) AS fx_to_vnd,
    ad_name AS entity_key,
    CAST(amount_spend AS NUMERIC) AS spend_native,
    CAST(amount_spend AS NUMERIC) AS spend_vnd,
    CAST(NULL AS NUMERIC) AS net_cost_vnd,
    CAST(NULL AS NUMERIC) AS max_delivery_budget_vnd,
    CAST(NULL AS NUMERIC) AS target_roi_budget_vnd,
    CAST(NULL AS NUMERIC) AS roas_bid,
    CAST(ROUND(SAFE_DIVIDE(amount_spend, NULLIF(cpm, 0)) * 1000) AS INT64) AS impressions,
    TRUE AS impressions_is_derived,
    CAST(NULL AS INT64) AS gross_impressions,
    CAST(reach AS INT64) AS reach,
    CAST(clicks AS INT64) AS clicks,
    CAST(NULL AS INT64) AS landing_page_views,
    CAST(page_engagement AS NUMERIC) AS page_engagement,
    CAST(NULL AS INT64) AS video_play_actions,
    CAST(NULL AS NUMERIC) AS video_play_seconds,
    CAST(NULL AS INT64) AS video_watched_2s,
    CAST(NULL AS INT64) AS video_watched_6s,
    CAST(NULL AS INT64) AS video_views_p25,
    CAST(NULL AS INT64) AS video_views_p50,
    CAST(NULL AS INT64) AS video_views_p75,
    CAST(NULL AS INT64) AS video_views_p100,
    CAST(NULL AS INT64) AS engaged_view,
    CAST(NULL AS INT64) AS engaged_view_15s,
    CAST(NULL AS INT64) AS follows,
    CAST(NULL AS INT64) AS likes,
    CAST(NULL AS INT64) AS comments,
    CAST(NULL AS INT64) AS shares,
    CAST(NULL AS INT64) AS profile_visits,
    CAST(NULL AS NUMERIC) AS live_views,
    CAST(NULL AS NUMERIC) AS live_10s_views,
    CAST(NULL AS NUMERIC) AS live_follows,
    CAST(NULL AS INT64) AS live_product_clicks,
    CAST(NULL AS INT64) AS results,
    CAST(NULL AS INT64) AS real_time_results,
    CAST(conversion_messaging_conversation_started_7d AS NUMERIC) AS messaging_conversations_7d,
    CAST(NULL AS NUMERIC) AS conversions,
    CAST(NULL AS NUMERIC) AS conversion_value_vnd,
    CAST(NULL AS NUMERIC) AS platform_orders,
    CAST(NULL AS NUMERIC) AS platform_gross_revenue_vnd
  FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_a`
  WHERE DATE_TRUNC(day, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
meta_us AS (
  SELECT
    day, 'META', 'Meta - LSOUL US', 'US', 'core_meta.core_ads_reporting_my',
    campaign_name, campaign_type, spent_source, 'VND', CAST(1 AS NUMERIC), ad_name,
    CAST(amount_spend AS NUMERIC), CAST(amount_spend AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    CAST(ROUND(SAFE_DIVIDE(amount_spend, NULLIF(cpm, 0)) * 1000) AS INT64), TRUE,
    CAST(NULL AS INT64), CAST(reach AS INT64), CAST(clicks AS INT64), CAST(NULL AS INT64),
    CAST(page_engagement AS NUMERIC),
    CAST(NULL AS INT64), CAST(NULL AS NUMERIC), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(conversion_messaging_conversation_started_7d AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
  FROM `marine-cycle-484213-b4.core_meta.core_ads_reporting_my`
  WHERE DATE_TRUNC(day, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
tiktok_auction_vn AS (
  SELECT
    inserted_at, 'TIKTOK', 'TikTok Ads - LSOUL VN',
    CASE country_code WHEN 'VN' THEN 'VIETNAM' WHEN 'TH' THEN 'THAILAND' WHEN 'US' THEN 'US' ELSE country_code END,
    'core_tiktok.core_reporting_basic_auction_ad',
    CAST(NULL AS STRING), 'AUCTION', CAST(NULL AS STRING), 'VND', CAST(1 AS NUMERIC), ad_id,
    CAST(spend AS NUMERIC), CAST(spend AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    impressions, FALSE, gross_impressions, reach, clicks, total_landing_page_view,
    CAST(NULL AS NUMERIC),
    video_play_actions, CAST(average_video_play * video_play_actions AS NUMERIC),
    video_watched_2s, video_watched_6s,
    video_views_p25, video_views_p50, video_views_p75, video_views_p100,
    engaged_view, engaged_view_15s, follows, likes, comments, shares, profile_visits,
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), live_product_clicks,
    result, real_time_result,
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
  FROM `marine-cycle-484213-b4.core_tiktok.core_reporting_basic_auction_ad`
  WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
tiktok_auction_th AS (
  SELECT
    inserted_at, 'TIKTOK', 'TikTok Ads - LSOUL TH',
    CASE country_code WHEN 'VN' THEN 'VIETNAM' WHEN 'TH' THEN 'THAILAND' WHEN 'US' THEN 'US' ELSE country_code END,
    'core_tiktok.core_thai_reporting_basic_auction_ad',
    CAST(NULL AS STRING), 'AUCTION', CAST(NULL AS STRING), 'THB', CAST(800 AS NUMERIC), ad_id,
    CAST(spend AS NUMERIC), CAST(spend * 800 AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    impressions, FALSE, gross_impressions, reach, clicks, total_landing_page_view,
    CAST(NULL AS NUMERIC),
    video_play_actions, CAST(average_video_play * video_play_actions AS NUMERIC),
    video_watched_2s, video_watched_6s,
    video_views_p25, video_views_p50, video_views_p75, video_views_p100,
    engaged_view, engaged_view_15s, follows, likes, comments, shares, profile_visits,
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), live_product_clicks,
    result, real_time_result,
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
  FROM `marine-cycle-484213-b4.core_tiktok.core_thai_reporting_basic_auction_ad`
  WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
tiktok_gmvmax_vn AS (
  SELECT
    inserted_at, 'TIKTOK', 'TikTok Shop GMV Max - VN', 'VIETNAM',
    'core_tiktok.core_tiktok_gmv_max_report',
    campaign_name, CONCAT('GMV MAX', IFNULL(CONCAT(' / ', bid_type), '')), tt_account_name,
    'VND', CAST(1 AS NUMERIC), campaign_id,
    cost, cost, net_cost, max_delivery_budget, target_roi_budget, roas_bid,
    CAST(NULL AS INT64), FALSE, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC),
    CAST(NULL AS INT64), CAST(NULL AS NUMERIC), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    live_views, `10_second_live_views`, live_follows, CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    orders, gross_revenue
  FROM `marine-cycle-484213-b4.core_tiktok.core_tiktok_gmv_max_report`
  WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
tiktok_gmvmax_th AS (
  SELECT
    inserted_at, 'TIKTOK', 'TikTok Shop GMV Max - TH', 'THAILAND',
    'core_tiktok.core_tiktok_thai_gmv_max_report',
    campaign_name, CONCAT('GMV MAX', IFNULL(CONCAT(' / ', bid_type), '')), tt_account_name,
    'THB', CAST(800 AS NUMERIC), campaign_id,
    cost, cost * 800, net_cost * 800, max_delivery_budget * 800, target_roi_budget * 800, roas_bid,
    CAST(NULL AS INT64), FALSE, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC),
    CAST(NULL AS INT64), CAST(NULL AS NUMERIC), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    live_views, `10_second_live_views`, live_follows, CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    orders, gross_revenue * 800
  FROM `marine-cycle-484213-b4.core_tiktok.core_tiktok_thai_gmv_max_report`
  WHERE DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
),
google_ads AS (
  SELECT
    day, 'GOOGLE ADS', CONCAT('Google Ads - ', account_name),
    CASE WHEN account_id = '6757483582' THEN 'US' ELSE 'VIETNAM' END,
    'reportdb.fn_ads_spend_ggads',
    campaign_name, CAST(NULL AS STRING), CAST(NULL AS STRING), 'VND', CAST(1 AS NUMERIC),
    CONCAT(campaign_name, ' || ', IFNULL(ad_group_name, '')),
    CAST(total_spend AS NUMERIC), CAST(total_spend AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC),
    CAST(total_impressions AS INT64), FALSE, CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(total_clicks AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC),
    CAST(NULL AS INT64), CAST(NULL AS NUMERIC), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS NUMERIC),
    CAST(total_conversions AS NUMERIC), CAST(total_conversion_value AS NUMERIC),
    CAST(NULL AS NUMERIC), CAST(NULL AS NUMERIC)
  FROM `marine-cycle-484213-b4.reportdb.fn_ads_spend_ggads`(i_number_year_back)
),
unioned AS (
  SELECT * FROM meta_vn
  UNION ALL SELECT * FROM meta_us
  UNION ALL SELECT * FROM tiktok_auction_vn
  UNION ALL SELECT * FROM tiktok_auction_th
  UNION ALL SELECT * FROM tiktok_gmvmax_vn
  UNION ALL SELECT * FROM tiktok_gmvmax_th
  UNION ALL SELECT * FROM google_ads
)
SELECT
  day, ads_channel, ads_account, market, campaign_name,
  ANY_VALUE(source_feed) AS source_feed,
  STRING_AGG(DISTINCT campaign_type, ' | ' ORDER BY campaign_type) AS campaign_type,
  STRING_AGG(DISTINCT spent_source, ' | ' ORDER BY spent_source) AS spent_source,
  ANY_VALUE(currency_code) AS currency_code,
  ANY_VALUE(fx_to_vnd) AS fx_to_vnd,
  COUNT(DISTINCT entity_key) AS active_entities,
  SUM(spend_native) AS spend_native,
  SUM(spend_vnd) AS spend_vnd,
  SUM(net_cost_vnd) AS net_cost_vnd,
  MAX(max_delivery_budget_vnd) AS max_delivery_budget_vnd,
  MAX(target_roi_budget_vnd) AS target_roi_budget_vnd,
  MAX(roas_bid) AS roas_bid,
  SUM(impressions) AS impressions,
  LOGICAL_OR(impressions_is_derived) AS impressions_is_derived,
  SUM(gross_impressions) AS gross_impressions,
  SUM(reach) AS reach,
  SUM(clicks) AS clicks,
  SUM(landing_page_views) AS landing_page_views,
  SUM(page_engagement) AS page_engagement,
  SUM(video_play_actions) AS video_play_actions,
  SUM(video_play_seconds) AS video_play_seconds,
  SUM(video_watched_2s) AS video_watched_2s,
  SUM(video_watched_6s) AS video_watched_6s,
  SUM(video_views_p25) AS video_views_p25,
  SUM(video_views_p50) AS video_views_p50,
  SUM(video_views_p75) AS video_views_p75,
  SUM(video_views_p100) AS video_views_p100,
  SUM(engaged_view) AS engaged_view,
  SUM(engaged_view_15s) AS engaged_view_15s,
  SUM(follows) AS follows,
  SUM(likes) AS likes,
  SUM(comments) AS comments,
  SUM(shares) AS shares,
  SUM(profile_visits) AS profile_visits,
  SUM(live_views) AS live_views,
  SUM(live_10s_views) AS live_10s_views,
  SUM(live_follows) AS live_follows,
  SUM(live_product_clicks) AS live_product_clicks,
  SUM(results) AS results,
  SUM(real_time_results) AS real_time_results,
  SUM(messaging_conversations_7d) AS messaging_conversations_7d,
  SUM(conversions) AS conversions,
  SUM(conversion_value_vnd) AS conversion_value_vnd,
  SUM(platform_orders) AS platform_orders,
  SUM(platform_gross_revenue_vnd) AS platform_gross_revenue_vnd,
  SAFE_DIVIDE(SUM(clicks), SUM(impressions)) AS ctr,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(clicks)) AS cpc_vnd,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(impressions)) * 1000 AS cpm_vnd,
  SAFE_DIVIDE(SUM(impressions), SUM(reach)) AS frequency,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(results)) AS cost_per_result_vnd,
  SAFE_DIVIDE(SUM(results), SUM(impressions)) AS result_rate,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(real_time_results)) AS cost_per_real_time_result_vnd,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(landing_page_views)) AS cost_per_landing_page_view_vnd,
  SAFE_DIVIDE(SUM(landing_page_views), SUM(clicks)) AS landing_page_view_rate,
  SAFE_DIVIDE(SUM(profile_visits), SUM(impressions)) AS profile_visit_rate,
  SAFE_DIVIDE(SUM(video_play_seconds), SUM(video_play_actions)) AS avg_video_play_seconds,
  SAFE_DIVIDE(SUM(video_views_p100), SUM(video_play_actions)) AS video_completion_rate,
  SAFE_DIVIDE(SUM(engaged_view_15s), SUM(impressions)) AS engaged_view_15s_rate,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(messaging_conversations_7d)) AS cost_per_messaging_conversation_vnd,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(conversions)) AS cost_per_conversion_vnd,
  SAFE_DIVIDE(SUM(conversion_value_vnd), SUM(spend_vnd)) AS conversion_value_roas,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(platform_orders)) AS cost_per_order_vnd,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(live_views)) AS cost_per_live_view_vnd,
  SAFE_DIVIDE(SUM(spend_vnd), SUM(live_10s_views)) AS cost_per_10s_live_view_vnd,
  SAFE_DIVIDE(SUM(platform_gross_revenue_vnd), SUM(spend_vnd)) AS platform_roas
FROM unioned
GROUP BY day, ads_channel, ads_account, market, campaign_name;
