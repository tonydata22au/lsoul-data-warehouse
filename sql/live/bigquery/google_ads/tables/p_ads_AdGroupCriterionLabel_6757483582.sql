CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AdGroupCriterionLabel_6757483582`
(
  ad_group_criterion_criterion_id INT64 OPTIONS(description="The ID of the criterion. This field is ignored for mutates."),
  label_id INT64 OPTIONS(description="Id of the label. Read only."),
  ad_group_criterion_label_ad_group_criterion STRING OPTIONS(description="The ad group criterion to which the label is attached."),
  ad_group_criterion_label_label STRING OPTIONS(description="The label assigned to the ad group criterion."),
  ad_group_criterion_label_resource_name STRING OPTIONS(description="The resource name of the ad group criterion label. Ad group criterion label resource names have the form: `customers/{customer_id}/adGroupCriterionLabels/{ad_group_id}~{criterion_id}~{label_id}`"),
  label_name STRING OPTIONS(description="The name of the label. This field is required and should not be empty when creating a new label. The length of this string should be between 1 and 80, inclusive."),
  label_resource_name STRING OPTIONS(description="Name of the resource. Label resource names have the form: `customers/{customer_id}/labels/{label_id}`")
)
PARTITION BY DATE(_PARTITIONTIME);
