CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_LocationBasedCampaignCriterion_4435779462`
(
  campaign_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored during mutate."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_criterion_bid_modifier FLOAT64 OPTIONS(description="The modifier for the bids when the criterion matches. The modifier must be in the range: 0.1 - 10.0. Most targetable criteria types support modifiers. Use 0 to opt out of a Device type."),
  campaign_criterion_negative BOOL OPTIONS(description="Whether to target (`false`) or exclude (`true`) the criterion.")
)
PARTITION BY DATE(_PARTITIONTIME);
