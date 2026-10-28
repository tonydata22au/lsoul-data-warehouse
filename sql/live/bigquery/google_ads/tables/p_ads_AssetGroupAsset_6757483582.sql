CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AssetGroupAsset_6757483582`
(
  asset_group_asset_asset STRING OPTIONS(description="The asset which this asset group asset is linking."),
  asset_group_asset_asset_group STRING OPTIONS(description="The asset group which this asset group asset is linking."),
  asset_group_asset_field_type STRING OPTIONS(description="The description of the placement of the asset within the asset group. For example: HEADLINE, YOUTUBE_VIDEO etc."),
  asset_group_asset_policy_summary_approval_status STRING OPTIONS(description="The overall approval status, which is calculated based on the status of its individual policy topic entries."),
  asset_group_asset_policy_summary_policy_topic_entries STRING OPTIONS(description="The list of policy findings."),
  asset_group_asset_policy_summary_review_status STRING OPTIONS(description="Where in the review process the resource is."),
  asset_group_asset_source STRING OPTIONS(description="Output only. Source of the asset group asset.")
)
PARTITION BY DATE(_PARTITIONTIME);
