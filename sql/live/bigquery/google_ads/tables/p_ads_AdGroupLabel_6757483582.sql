CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroupLabel_6757483582`
(
  ad_group_id INT64 OPTIONS(description="The ID of the ad group."),
  label_id INT64 OPTIONS(description="Id of the label. Read only."),
  ad_group_label_ad_group STRING OPTIONS(description="The ad group to which the label is attached."),
  ad_group_label_label STRING OPTIONS(description="The label assigned to the ad group."),
  ad_group_label_resource_name STRING OPTIONS(description="The resource name of the ad group label. Ad group label resource names have the form: `customers/{customer_id}/adGroupLabels/{ad_group_id}~{label_id}`"),
  ad_group_name STRING OPTIONS(description="The name of the ad group. This field is required and should not be empty when creating new ad groups. It must contain fewer than 255 UTF-8 full-width characters. It must not contain any null (code point 0x0), NL line feed (code point 0xA) or carriage return (code point 0xD) characters."),
  label_name STRING OPTIONS(description="The name of the label. This field is required and should not be empty when creating a new label. The length of this string should be between 1 and 80, inclusive."),
  label_resource_name STRING OPTIONS(description="Name of the resource. Label resource names have the form: `customers/{customer_id}/labels/{label_id}`")
)
PARTITION BY DATE(_PARTITIONTIME);
