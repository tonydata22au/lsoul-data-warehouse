CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroupCriterion_6757483582`
(
  ad_group_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored for mutates."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  ad_group_criterion_ad_group STRING OPTIONS(description="The ad group to which the criterion belongs."),
  ad_group_criterion_bid_modifier FLOAT64 OPTIONS(description="The modifier for the bid when the criterion matches. The modifier must be in the range: 0.1 - 10.0. Most targetable criteria types support modifiers."),
  ad_group_criterion_cpc_bid_micros INT64 OPTIONS(description="The CPC (cost-per-click) bid."),
  ad_group_criterion_cpm_bid_micros INT64 OPTIONS(description="The CPM (cost-per-thousand viewable impressions) bid."),
  ad_group_criterion_cpv_bid_micros INT64 OPTIONS(description="The CPC (cost-per-view) bid."),
  ad_group_criterion_display_name STRING OPTIONS(description="The display name of the criterion. This field is ignored for mutates."),
  ad_group_criterion_negative BOOL OPTIONS(description="Whether to target (`false`) or exclude (`true`) the criterion."),
  ad_group_criterion_status STRING OPTIONS(description="The status of the criterion."),
  ad_group_criterion_type STRING OPTIONS(description="The type of the criterion."),
  ad_group_name STRING OPTIONS(description="The name of the ad group. This field is required and should not be empty when creating new ad groups. It must contain fewer than 255 UTF-8 full-width characters. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters.")
)
PARTITION BY DATE(_PARTITIONTIME);
