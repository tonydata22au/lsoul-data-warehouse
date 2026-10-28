CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_ads_spend_ggads(i_number_year_back INT64)
AS
WITH combined_ad_level_data AS (
  -- ==========================================
  -- ACCOUNT 1: 4435779462 (Campaign Level Only)
  -- ==========================================
  SELECT DISTINCT
    '4435779462' AS account_id,
    'Store NT' AS account_name,
    stats.segments_date AS day,
    stats.campaign_id,
    camp.campaign_name,
    -- Since this account has no Ad Groups or Ads, we populate these columns as NULL / N/A
    CAST(NULL AS INT64) AS ad_group_id,
    'N/A (Campaign Level Only)' AS ad_group_name,
    CAST(NULL AS INT64) AS ad_id,
    
    -- Core Metrics (Cost converted from micros)
    stats.metrics_impressions AS impressions,
    stats.metrics_clicks AS clicks,
    ROUND(stats.metrics_cost_micros / 1000000, 2) AS cost,
    stats.metrics_conversions AS conversions,
    stats.metrics_conversions_value AS conversion_value
  FROM 
    `marine-cycle-484213-b4.google_ads.ads_CampaignBasicStats_4435779462` AS stats
  LEFT JOIN 
    `marine-cycle-484213-b4.google_ads.ads_Campaign_4435779462` AS camp
    ON stats.campaign_id = camp.campaign_id


  UNION ALL

  -- ==========================================
  -- ACCOUNT 2: 6757483582 (Detailed Ad Level)
  -- ==========================================
  SELECT DISTINCT
    '6757483582' AS account_id,
    'Website US' AS account_name,
    stats.segments_date AS day,
    stats.campaign_id,
    camp.campaign_name,
    stats.ad_group_id,
    ad_group.ad_group_name,
    stats.ad_group_ad_ad_id AS ad_id,
    
    -- Core Metrics
    stats.metrics_impressions AS impressions,
    stats.metrics_clicks AS clicks,
    ROUND(stats.metrics_cost_micros / 1000000, 2) AS cost,
    stats.metrics_conversions AS conversions,
    stats.metrics_conversions_value AS conversion_value
  FROM 
    `marine-cycle-484213-b4.google_ads.ads_AdStats_6757483582` AS stats
  LEFT JOIN 
    `marine-cycle-484213-b4.google_ads.ads_Campaign_6757483582` AS camp
    ON stats.campaign_id = camp.campaign_id
  LEFT JOIN 
    `marine-cycle-484213-b4.google_ads.ads_AdGroup_6757483582` AS ad_group
    ON stats.ad_group_id = ad_group.ad_group_id
)

-- Final Aggregation & Marketing KPI Calculations
SELECT
  day,
  account_id,
  account_name,
  --campaign_id,
  campaign_name,
  --ad_group_id,
  ad_group_name,
  --ad_id,
  
  -- Performance Summaries
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  SUM(cost) AS total_spend,
  SUM(conversions) AS total_conversions,
  SUM(conversion_value) AS total_conversion_value,
  
  -- Executive Calculated KPIs
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_percent,
  ROUND(SAFE_DIVIDE(SUM(cost), SUM(clicks)), 2) AS cpc,
  ROUND(SAFE_DIVIDE(SUM(cost), SUM(conversions)), 2) AS cost_per_conversion
FROM
  combined_ad_level_data 
WHERE DATE_TRUNC(day, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
GROUP BY
  1, 2, 3, 4 , 5
ORDER BY
  day DESC, 
  total_spend DESC;
