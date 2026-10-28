CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroupBidModifier_6757483582`
(
  ad_group_bid_modifier_criterion_id INT64 OPTIONS(description="The ID of the criterion to bid modify. This field is ignored for mutates."),
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  ad_group_bid_modifier_ad_group STRING OPTIONS(description="The ad group to which this criterion belongs."),
  ad_group_bid_modifier_base_ad_group STRING OPTIONS(description="The base ad group from which this draft/trial adgroup bid modifier was created. If ad_group is a base ad group then this field will be equal to ad_group. If the ad group was created in the draft or trial and has no corresponding base ad group, then this field will be null. This field is readonly."),
  ad_group_bid_modifier_bid_modifier FLOAT64 OPTIONS(description="The modifier for the bid when the criterion matches. The modifier must be in the range: 0.1 - 10.0. The range is 1.0 - 6.0 for PreferredContent. Use 0 to opt out of a Device type."),
  ad_group_bid_modifier_bid_modifier_source STRING OPTIONS(description="Bid modifier source."),
  ad_group_bid_modifier_device_type STRING OPTIONS(description="Type of the device."),
  ad_group_bid_modifier_resource_name STRING OPTIONS(description="The resource name of the ad group bid modifier. Ad group bid modifier resource names have the form: `customers/{customer_id}/adGroupBidModifiers/{ad_group_id}~{criterion_id}`"),
  ad_group_name STRING OPTIONS(description="The name of the ad group. This field is required and should not be empty when creating new ad groups. It must contain fewer than 255 UTF-8 full-width characters. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters.")
)
PARTITION BY DATE(_PARTITIONTIME);
