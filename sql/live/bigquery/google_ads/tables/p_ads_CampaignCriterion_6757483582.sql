CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignCriterion_6757483582`
(
  campaign_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored during mutate."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  campaign_criterion_bid_modifier FLOAT64 OPTIONS(description="The modifier for the bids when the criterion matches. The modifier must be in the range: 0.1 - 10.0. Most targetable criteria types support modifiers. Use 0 to opt out of a Device type."),
  campaign_criterion_campaign STRING OPTIONS(description="The campaign to which the criterion belongs."),
  campaign_criterion_device_type STRING OPTIONS(description="Type of the device."),
  campaign_criterion_display_name STRING OPTIONS(description="The display name of the criterion. This field is ignored for mutates."),
  campaign_criterion_negative BOOL OPTIONS(description="Whether to target (`false`) or exclude (`true`) the criterion."),
  campaign_criterion_status STRING OPTIONS(description="The status of the criterion."),
  campaign_criterion_type STRING OPTIONS(description="The type of the criterion."),
  campaign_name STRING OPTIONS(description="The name of the campaign. This field is required and should not be empty when creating new campaigns. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters.")
)
PARTITION BY DATE(_PARTITIONTIME);
