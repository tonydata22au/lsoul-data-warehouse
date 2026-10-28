CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Asset_6757483582`
(
  asset_id INT64 OPTIONS(description="Output only. The ID of the asset."),
  asset_final_urls STRING OPTIONS(description="Output only. Type of the asset."),
  asset_name STRING OPTIONS(description="Optional name of the asset."),
  asset_source STRING OPTIONS(description="Output only. Source of the asset."),
  asset_type STRING OPTIONS(description="A list of possible final URLs after all cross domain redirects."),
  segments_conversion_action STRING OPTIONS(description="Resource name of the conversion action.")
)
PARTITION BY DATE(_PARTITIONTIME);
