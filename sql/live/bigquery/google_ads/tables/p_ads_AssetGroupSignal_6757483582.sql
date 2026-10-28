CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AssetGroupSignal_6757483582`
(
  asset_group_signal_asset_group STRING OPTIONS(description="The asset group which this asset group signal belongs to."),
  asset_group_signal_audience_audience STRING OPTIONS(description="The Audience resource name."),
  asset_group_signal_resource_name STRING OPTIONS(description="The resource name of the asset group signal. Asset group signal resource name have the form: customers/{customer_id}/assetGroupSignals/{asset_group_id}~{signal_id}")
)
PARTITION BY DATE(_PARTITIONTIME);
