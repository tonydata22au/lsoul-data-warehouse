--DROP TABLE `marine-cycle-484213-b4.core_tiktok.core_reporting_basic_auction_ad`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_tiktok.core_reporting_basic_auction_ad`
PARTITION BY inserted_at
CLUSTER BY  ad_id, country_code
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
inserted_at,
ad_id, 
country_code, 
spend, 
cpc, 
cpm, 
impressions,
gross_impressions,
clicks,
ctr,
reach,
frequency,
result,
cost_per_result,
result_rate,
real_time_result,
real_time_cost_per_result,
real_time_result_rate,
video_play_actions,
video_watched_2s,
video_watched_6s,
average_video_play,
video_views_p25,
video_views_p50,
video_views_p75,
video_views_p100,
engaged_view,
engaged_view_15s,
follows,
likes,
comments,
shares,
profile_visits,
profile_visits_rate,
live_product_clicks,
total_landing_page_view,
cost_per_landing_page_view,
landing_page_view_rate
FROM `marine-cycle-484213-b4.stg_tiktok.stg_reporting_basic_auction_ad`
WHERE proc_date >= '2026-01-01'


