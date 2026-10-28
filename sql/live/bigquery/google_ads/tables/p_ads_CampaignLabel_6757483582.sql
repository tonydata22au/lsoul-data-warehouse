CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_CampaignLabel_6757483582`
(
  campaign_id INT64 OPTIONS(description="The ID of the campaign."),
  label_id INT64 OPTIONS(description="Id of the label. Read only."),
  campaign_label_campaign STRING OPTIONS(description="The campaign to which the label is attached."),
  campaign_label_label STRING OPTIONS(description="The label assigned to the campaign."),
  campaign_label_resource_name STRING OPTIONS(description="Name of the resource. Campaign label resource names have the form: `customers/{customer_id}/campaignLabels/{campaign_id}~{label_id}`"),
  campaign_name STRING OPTIONS(description="The name of the campaign. This field is required and should not be empty when creating new campaigns. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters."),
  label_name STRING OPTIONS(description="The name of the label. This field is required and should not be empty when creating a new label. The length of this string should be between 1 and 80, inclusive."),
  label_resource_name STRING OPTIONS(description="Name of the resource. Label resource names have the form: `customers/{customer_id}/labels/{label_id}`")
)
PARTITION BY DATE(_PARTITIONTIME);
