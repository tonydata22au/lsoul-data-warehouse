CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Budget_6757483582`
(
  campaign_budget_id INT64 OPTIONS(description="The ID of the campaign budget. A campaign budget is created using the CampaignBudgetService create operation and is assigned a budget ID. A budget ID can be shared across different campaigns; the system will then allocate the campaign budget among different campaigns to get optimum results."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  campaign_budget_amount_micros INT64 OPTIONS(description="The amount of the budget, in the local currency for the account. Amount is specified in micros, where one million is equivalent to one currency unit. Monthly spend is capped at 30.4 times this amount."),
  campaign_budget_delivery_method STRING OPTIONS(description="The delivery method that determines the rate at which the campaign budget is spent. Defaults to STANDARD if unspecified in a create operation."),
  campaign_budget_explicitly_shared BOOL OPTIONS(description="Specifies whether the budget is explicitly shared. Defaults to true if unspecified in a create operation. If true, the budget was created with the purpose of sharing across one or more campaigns. If false, the budget was created with the intention of only being used with a single campaign. The budget's name and status will stay in sync with the campaign's name and status. Attempting to share the budget with a second campaign will result in an error. A non-shared budget can become an explicitly shared. The same operation must also assign the budget a name. A shared campaign budget can never become non-shared."),
  campaign_budget_has_recommended_budget BOOL OPTIONS(description="Indicates whether there is a recommended budget for this campaign budget. This field is read-only."),
  campaign_budget_name STRING OPTIONS(description="The name of the campaign budget. When creating a campaign budget through CampaignBudgetService, every explicitly shared campaign budget must have a non-null, non-empty name. Campaign budgets that are not explicitly shared derive their name from the attached campaign's name. The length of this string must be between 1 and 255, inclusive, in UTF-8 bytes, (trimmed)."),
  campaign_budget_period STRING OPTIONS(description="Period over which to spend the budget. Defaults to DAILY if not specified."),
  campaign_budget_recommended_budget_amount_micros INT64 OPTIONS(description="The recommended budget amount. If no recommendation is available, this will be set to the budget amount. Amount is specified in micros, where one million is equivalent to one currency unit. This field is read-only."),
  campaign_budget_reference_count INT64 OPTIONS(description="The number of campaigns actively using the budget. This field is read-only."),
  campaign_budget_status STRING OPTIONS(description="The status of this campaign budget. This field is read-only."),
  campaign_budget_total_amount_micros INT64 OPTIONS(description="The lifetime amount of the budget, in the local currency for the account. Amount is specified in micros, where one million is equivalent to one currency unit."),
  customer_descriptive_name STRING OPTIONS(description="Optional, non-unique descriptive name of the customer.")
)
PARTITION BY DATE(_PARTITIONTIME);
