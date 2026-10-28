CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroup_4435779462`
(
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_ad_rotation_mode STRING OPTIONS(description="The ad rotation mode of the ad group."),
  ad_group_cpc_bid_micros INT64 OPTIONS(description="The maximum CPC (cost-per-click) bid."),
  ad_group_cpm_bid_micros INT64 OPTIONS(description="The maximum CPM (cost-per-thousand viewable impressions) bid."),
  ad_group_cpv_bid_micros INT64 OPTIONS(description="The CPV (cost-per-view) bid."),
  ad_group_display_custom_bid_dimension STRING OPTIONS(description="Allows advertisers to specify a targeting dimension on which to place absolute bids. This is only applicable for campaigns that target only the display network and not search."),
  ad_group_effective_target_cpa_micros INT64 OPTIONS(description="The effective target CPA (cost-per-acquisition). This field is read-only."),
  ad_group_effective_target_cpa_source STRING OPTIONS(description="Source of the effective target CPA. This field is read-only."),
  ad_group_effective_target_roas FLOAT64 OPTIONS(description="The effective target ROAS (return-on-ad-spend). This field is read-only."),
  ad_group_effective_target_roas_source STRING OPTIONS(description="Source of the effective target ROAS. This field is read-only."),
  ad_group_name STRING OPTIONS(description="The name of the ad group. This field is required and should not be empty when creating new ad groups. It must contain fewer than 255 UTF-8 full-width characters. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters."),
  ad_group_status STRING OPTIONS(description="The status of the ad group."),
  ad_group_tracking_url_template STRING OPTIONS(description="The URL template for constructing a tracking URL."),
  ad_group_type STRING OPTIONS(description="The type of the ad group."),
  ad_group_url_custom_parameters STRING OPTIONS(description="The list of mappings used to substitute custom parameter tags in a `tracking_url_template`, `final_urls`, or `mobile_final_urls`."),
  campaign_bidding_strategy STRING OPTIONS(description="Portfolio bidding strategy used by campaign."),
  campaign_bidding_strategy_type STRING OPTIONS(description="The type of bidding strategy. A bidding strategy can be created by setting either the bidding scheme to create a standard bidding strategy or the `bidding_strategy` field to create a portfolio bidding strategy. This field is read-only."),
  campaign_manual_cpc_enhanced_cpc_enabled BOOL OPTIONS(description="Whether bids are to be enhanced based on conversion optimizer data."),
  campaign_percent_cpc_enhanced_cpc_enabled BOOL OPTIONS(description="Adjusts the bid for each auction upward or downward, depending on the likelihood of a conversion. Individual bids may exceed cpc_bid_ceiling_micros, but the average bid amount for a campaign should not.")
)
PARTITION BY DATE(_PARTITIONTIME);
