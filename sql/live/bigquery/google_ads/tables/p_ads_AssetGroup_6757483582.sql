CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AssetGroup_6757483582`
(
  asset_group_id STRING OPTIONS(description="Output only. The ID of the asset group."),
  asset_group_campaign STRING OPTIONS(description="Immutable. The campaign with which this asset group is associated. The asset which is linked to the asset group."),
  asset_group_final_mobile_urls STRING OPTIONS(description="A list of final mobile URLs after all cross domain redirects. In performance max, by default, the urls are eligible for expansion unless opted out."),
  asset_group_final_urls STRING OPTIONS(description="A list of final URLs after all cross domain redirects. In performance max, by default, the urls are eligible for expansion unless opted out."),
  asset_group_name STRING OPTIONS(description="Required. Name of the asset group. Required. It must have a minimum length of 1 and maximum length of 128. It must be unique under a campaign."),
  asset_group_status STRING OPTIONS(description="The status of the asset group.")
)
PARTITION BY DATE(_PARTITIONTIME);
