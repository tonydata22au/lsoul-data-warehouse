CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_ads_media_daily`(
  i_number_year_back INT64
)
OPTIONS (
  description = "LSOUL marketing performance report: ads media metrics by day x channel x market x level_1/2/3 commercial taxonomy x buying_type. Built on fn_ads_metrics_daily so spend reconciles to the platforms exactly. Includes TikTok Thailand (previously missing) and Meta recruitment spend (flagged is_sale_campaign=FALSE). 60 metrics covering reach, traffic, video/creative, social engagement, leads and TikTok Shop commerce. buying_type separates Auction delivery from GMV Max commerce so CPM/CPC stay meaningful. All money in VND; all rates recomputed from components."
)
AS (

/*=====================================================================================
-- reportdb.fn_ads_media_daily(i_number_year_back INT64)
-- -------------------------------------------------------------------------------------
-- LSOUL marketing performance report layer: ads media metrics mapped onto the commercial
-- taxonomy (level_1 order source / level_2 sale channel / level_3 touchpoint).
--
-- Built entirely on reportdb.fn_ads_metrics_daily(), so spend reconciles to the platforms
-- by construction. All money is VND; for native-currency reconciliation against the
-- TikTok Thailand UI, use fn_ads_metrics_daily (spend_native + currency_code).
--
-- Grain : period_date x ads_channel x market x level_1 x level_2 x level_3 x buying_type
-- Params: i_number_year_back  0 = current year only, 1 = current + previous year, ...
--
-- CHANGES vs the previous version (2026-09-06)
--   + TikTok Thailand auction + GMV Max feeds added   (were missing entirely: 1.23B VND YTD)
--   + Meta recruitment campaigns no longer dropped; routed to Non-Sale / Recruitment and
--     flagged is_sale_campaign = FALSE            (68.7M VND YTD)
--     -> filter is_sale_campaign = TRUE to reproduce the old spend figures
--   + market column added; Thai Meta store spend no longer misrouted to 'VN Offline Store'
--   + buying_type column (Auction | GMV Max) - GMV Max reports spend and orders but no
--     impressions/clicks, so merging it with auction delivery inflated CPM ~26x
--   + 60 metric columns (was 6). Existing 6 keep their names and meaning.
--   + every rate recomputed from components at output grain - never AVG-then-SUM
--
-- Backward-compatible columns: period_date, ads_channel, level_1, level_2, level_3,
--                              spend, reach, impressions, clicks, engagements, video_views

SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_ads_media_daily`(0)

=====================================================================================*/

WITH mapped AS (
  SELECT
    day AS period_date,
    IF(ads_channel = 'GOOGLE ADS', 'Google Ads', ads_channel) AS channel,

    -- Meta campaigns with no campaign_type are recruitment ads (TUYEN DUNG), not marketing
    (ads_channel <> 'META' OR campaign_type IS NOT NULL) AS is_sale_campaign,

    -- separates auction delivery (has impressions/clicks) from GMV Max commerce (spend +
    -- orders only). Without this split, mixing them makes CPM/CPC meaningless.
    IF(campaign_type LIKE 'GMV MAX%', 'GMV Max', 'Auction') AS buying_type,

    -- level_1: order source
    CASE
      WHEN ads_channel = 'META' AND campaign_type IS NULL THEN 'Non-Sale'
      WHEN ads_account = 'Meta - LSOUL US'                THEN 'Sale Online'
      WHEN ads_channel = 'META' THEN
        CASE spent_source
          WHEN 'SPENT STORE'     THEN 'Store'
          WHEN 'SPENT SOCIAL'    THEN 'Sale Online'
          WHEN 'SPENT ECOMMERCE' THEN 'Sale Ecommerce'
          ELSE spent_source
        END
      WHEN ads_account = 'TikTok Ads - LSOUL VN' THEN
        CASE market
          WHEN 'VIETNAM'  THEN 'Store'
          WHEN 'THAILAND' THEN 'Store'
          WHEN 'US'       THEN 'Sale Online'
          ELSE 'Sale Ecommerce'
        END
      WHEN ads_channel = 'TIKTOK'                  THEN 'Sale Ecommerce'
      WHEN ads_account = 'Google Ads - Website US' THEN 'Sale Online'
      ELSE 'Store'
    END AS level_1,

    -- level_2: sale channel
    CASE
      WHEN ads_channel = 'META' AND campaign_type IS NULL THEN 'Recruitment'
      WHEN ads_account = 'Meta - LSOUL US'                THEN 'VN Online'
      WHEN ads_channel = 'META' AND market = 'THAILAND'
           AND spent_source IN ('SPENT SOCIAL','SPENT ECOMMERCE') THEN 'TL Ecommerce'
      WHEN ads_channel = 'META' AND market = 'THAILAND'   THEN 'TL Offline Store'
      WHEN ads_channel = 'META' AND spent_source = 'SPENT SOCIAL'    THEN 'VN Online'
      WHEN ads_channel = 'META' AND spent_source = 'SPENT ECOMMERCE' THEN 'VN Ecommerce'
      WHEN ads_channel = 'META'                          THEN 'VN Offline Store'
      WHEN ads_account = 'TikTok Ads - LSOUL VN' THEN
        CASE market
          WHEN 'VIETNAM'  THEN 'VN Offline Store'
          WHEN 'THAILAND' THEN 'TL Offline Store'
          WHEN 'US'       THEN 'VN Online'
          ELSE 'VN Ecommerce'
        END
      WHEN ads_account = 'TikTok Ads - LSOUL TH'      THEN 'TL Ecommerce'
      WHEN ads_account = 'TikTok Shop GMV Max - VN'   THEN 'VN Ecommerce'
      WHEN ads_account = 'TikTok Shop GMV Max - TH'   THEN 'TL Ecommerce'
      WHEN ads_account = 'Google Ads - Website US'    THEN 'VN Online'
      ELSE 'VN Offline Store'
    END AS level_2,

    -- level_3: touchpoint
    CASE
      WHEN ads_channel = 'META' THEN
        CASE
          WHEN campaign_type LIKE '%FB%'              THEN 'Facebook'
          WHEN campaign_type LIKE '%IG%'              THEN 'Instagram'
          WHEN UPPER(campaign_type) LIKE '%WEB%'      THEN 'Website'
          WHEN campaign_type IS NULL                  THEN 'Unclassified'
          WHEN ads_account = 'Meta - LSOUL US'        THEN 'Website'
          ELSE 'Store Nguyễn Trãi'
        END
      WHEN ads_account = 'TikTok Ads - LSOUL VN' THEN
        CASE market
          WHEN 'VIETNAM'  THEN 'Store Nguyễn Trãi'
          WHEN 'THAILAND' THEN 'Emsphere'
          WHEN 'US'       THEN 'Website'
          ELSE 'Tiktok'
        END
      WHEN ads_account = 'TikTok Ads - LSOUL TH'    THEN 'Tiktok'
      WHEN ads_account = 'TikTok Shop GMV Max - VN' THEN 'Tiktok'
      WHEN ads_account = 'TikTok Shop GMV Max - TH' THEN 'Tiktok'
      WHEN ads_account = 'Google Ads - Website US'  THEN 'Website'
      ELSE 'Store Nguyễn Trãi'
    END AS level_3,

    * EXCEPT (day, ads_channel, market)
  FROM `marine-cycle-484213-b4.reportdb.fn_ads_metrics_daily`(i_number_year_back)
),

agg AS (
  SELECT
    period_date,
    channel AS ads_channel,
    level_1,
    level_2,
    level_3,
    buying_type,
    is_sale_campaign,

    -- ============ investment ============
    SUM(spend_vnd)                                                  AS spend,
    COUNT(DISTINCT campaign_name)                                   AS campaigns,
    SUM(active_entities)                                            AS active_ads,

    -- ============ reach & delivery ============
    SUM(impressions)                                                AS impressions,
    LOGICAL_OR(impressions_is_derived)                              AS impressions_is_derived,
    SUM(reach)                                                      AS reach,
    SAFE_DIVIDE(SUM(impressions), SUM(reach))                       AS frequency,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(impressions)) * 1000            AS cpm_vnd,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(reach)) * 1000                  AS cost_per_1k_reach_vnd,

    -- ============ traffic ============
    SUM(clicks)                                                     AS clicks,
    SAFE_DIVIDE(SUM(clicks), SUM(impressions))                      AS ctr,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(clicks))                        AS cpc_vnd,
    SUM(landing_page_views)                                         AS landing_page_views,
    SAFE_DIVIDE(SUM(landing_page_views), SUM(clicks))               AS landing_page_view_rate,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(landing_page_views))            AS cost_per_landing_page_view_vnd,

    -- ============ video / creative ============
    SUM(engaged_view_15s)                                           AS video_views,
    SUM(video_play_actions)                                         AS video_play_actions,
    SUM(video_watched_2s)                                           AS video_watched_2s,
    SUM(video_watched_6s)                                           AS video_watched_6s,
    SUM(video_views_p25)                                            AS video_views_p25,
    SUM(video_views_p50)                                            AS video_views_p50,
    SUM(video_views_p75)                                            AS video_views_p75,
    SUM(video_views_p100)                                           AS video_views_p100,
    SAFE_DIVIDE(SUM(video_watched_2s), SUM(impressions))            AS hook_rate,
    SAFE_DIVIDE(SUM(video_watched_6s), SUM(video_watched_2s))       AS hold_rate,
    SAFE_DIVIDE(SUM(video_views_p100), SUM(video_play_actions))     AS video_completion_rate,
    SAFE_DIVIDE(SUM(video_play_seconds), SUM(video_play_actions))   AS avg_video_play_seconds,
    SAFE_DIVIDE(SUM(engaged_view_15s), SUM(impressions))            AS engaged_view_15s_rate,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(engaged_view_15s))              AS cost_per_video_view_vnd,

    -- ============ social engagement ============
    SUM(page_engagement)                                            AS engagements,
    SUM(likes)                                                      AS likes,
    SUM(comments)                                                   AS comments,
    SUM(shares)                                                     AS shares,
    SUM(follows)                                                    AS follows,
    SUM(profile_visits)                                             AS profile_visits,
    IFNULL(SUM(likes),0) + IFNULL(SUM(comments),0) + IFNULL(SUM(shares),0)
      + IFNULL(SUM(follows),0) + IFNULL(SUM(profile_visits),0)      AS social_actions,
    CAST(IFNULL(SUM(page_engagement),0) AS NUMERIC)
      + IFNULL(SUM(likes),0) + IFNULL(SUM(comments),0) + IFNULL(SUM(shares),0)
      + IFNULL(SUM(follows),0) + IFNULL(SUM(profile_visits),0)      AS total_engagements,
    SAFE_DIVIDE(
      CAST(IFNULL(SUM(page_engagement),0) AS NUMERIC)
        + IFNULL(SUM(likes),0) + IFNULL(SUM(comments),0) + IFNULL(SUM(shares),0)
        + IFNULL(SUM(follows),0) + IFNULL(SUM(profile_visits),0),
      SUM(impressions))                                             AS engagement_rate,
    SAFE_DIVIDE(SUM(spend_vnd),
      NULLIF(CAST(IFNULL(SUM(page_engagement),0) AS NUMERIC)
        + IFNULL(SUM(likes),0) + IFNULL(SUM(comments),0) + IFNULL(SUM(shares),0)
        + IFNULL(SUM(follows),0) + IFNULL(SUM(profile_visits),0), 0))
                                                                    AS cost_per_engagement_vnd,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(follows))                       AS cost_per_follower_vnd,
    SAFE_DIVIDE(SUM(profile_visits), SUM(impressions))              AS profile_visit_rate,

    -- ============ leads & conversions ============
    SUM(messaging_conversations_7d)                                 AS messaging_conversations_7d,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(messaging_conversations_7d))    AS cost_per_messaging_conversation_vnd,
    SUM(results)                                                    AS results,
    SAFE_DIVIDE(SUM(results), SUM(impressions))                     AS result_rate,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(results))                       AS cost_per_result_vnd,
    SUM(conversions)                                                AS conversions,
    SUM(conversion_value_vnd)                                       AS conversion_value_vnd,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(conversions))                   AS cost_per_conversion_vnd,
    SAFE_DIVIDE(SUM(conversion_value_vnd), SUM(spend_vnd))          AS conversion_value_roas,

    -- ============ TikTok Shop commerce ============
    SUM(platform_orders)                                            AS platform_orders,
    SUM(platform_gross_revenue_vnd)                                 AS platform_gross_revenue_vnd,
    SAFE_DIVIDE(SUM(platform_gross_revenue_vnd), SUM(spend_vnd))    AS platform_roas,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(platform_orders))               AS cost_per_order_vnd,
    SUM(live_views)                                                 AS live_views,
    SUM(live_10s_views)                                             AS live_10s_views,
    SUM(live_follows)                                               AS live_follows,
    SAFE_DIVIDE(SUM(spend_vnd), SUM(live_views))                    AS cost_per_live_view_vnd
  FROM mapped
  GROUP BY period_date, channel, level_1, level_2, level_3, buying_type, is_sale_campaign
)

SELECT
  agg.*,
  SAFE_DIVIDE(spend, SUM(spend) OVER (PARTITION BY period_date))                AS pct_of_day_spend,
  SAFE_DIVIDE(spend, SUM(spend) OVER (PARTITION BY period_date, ads_channel))   AS pct_of_channel_day_spend,
  SAFE_DIVIDE(spend, SUM(spend) OVER (PARTITION BY period_date, level_2))       AS pct_of_sale_channel_day_spend
FROM agg
);