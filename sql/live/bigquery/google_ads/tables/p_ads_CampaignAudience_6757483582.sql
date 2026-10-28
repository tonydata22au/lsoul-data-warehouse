CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignAudience_6757483582`
(
  campaign_criterion_criterion_id STRING OPTIONS(description="Output only. The ID of the criterion. This field is ignored during mutate."),
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_base_campaign STRING OPTIONS(description="The resource name of the base campaign of a draft or experiment campaign. For base campaigns, this is equal to `resource_name`. This field is read-only."),
  campaign_criterion_bid_modifier STRING OPTIONS(description="Portfolio bidding strategy used by campaign.")
)
PARTITION BY DATE(_PARTITIONTIME);
