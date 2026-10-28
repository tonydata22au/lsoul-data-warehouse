CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Gender_6757483582`
(
  ad_group_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored for mutates."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  ad_group_base_ad_group STRING OPTIONS(description="For draft or experiment ad groups, this field is the resource name of the base ad group from which this ad group was created. If a draft or experiment ad group does not have a base ad group, then this field is null. For base ad groups, this field equals the ad group resource name. This field is read-only."),
  ad_group_criterion_bid_modifier FLOAT64 OPTIONS(description="The modifier for the bid when the criterion matches. The modifier must be in the range: 0.1 - 10.0. Most targetable criteria types support modifiers."),
  ad_group_criterion_effective_cpc_bid_micros INT64 OPTIONS(description="The effective CPC (cost-per-click) bid."),
  ad_group_criterion_effective_cpc_bid_source STRING OPTIONS(description="Source of the effective CPC bid."),
  ad_group_criterion_effective_cpm_bid_micros INT64 OPTIONS(description="The effective CPM (cost-per-thousand viewable impressions) bid."),
  ad_group_criterion_effective_cpm_bid_source STRING OPTIONS(description="Source of the effective CPM bid."),
  ad_group_criterion_final_mobile_urls STRING OPTIONS(description="The list of possible final mobile URLs after all cross-domain redirects."),
  ad_group_criterion_final_urls STRING OPTIONS(description="The list of possible final URLs after all cross-domain redirects for the ad."),
  ad_group_criterion_gender_type STRING OPTIONS(description="Type of the gender."),
  ad_group_criterion_negative BOOL OPTIONS(description="Whether to target (`false`) or exclude (`true`) the criterion. This field is immutable. To switch a criterion from positive to negative, remove then re-add it."),
  ad_group_criterion_status STRING OPTIONS(description="The status of the criterion."),
  ad_group_criterion_tracking_url_template STRING OPTIONS(description="The URL template for constructing a tracking URL."),
  ad_group_criterion_url_custom_parameters STRING OPTIONS(description="The list of mappings used to substitute custom parameter tags in a `tracking_url_template`, `final_urls`, or `mobile_final_urls`."),
  ad_group_targeting_setting_target_restrictions STRING OPTIONS(description="The per-targeting-dimension setting to restrict the reach of your campaign or ad group."),
  bidding_strategy_name STRING OPTIONS(description="The name of the bidding strategy. All bidding strategies within an account must be named distinctly. The length of this string should be between 1 and 255, inclusive, in UTF-8 bytes, (trimmed)."),
  bidding_strategy_type STRING OPTIONS(description="The type of the bidding strategy. Create a bidding strategy by setting the bidding scheme. This field is read-only."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  campaign_bidding_strategy STRING OPTIONS(description="Portfolio bidding strategy used by campaign.")
)
PARTITION BY DATE(_PARTITIONTIME);
