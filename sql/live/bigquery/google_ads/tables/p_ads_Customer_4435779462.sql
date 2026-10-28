CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Customer_4435779462`
(
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  customer_auto_tagging_enabled BOOL OPTIONS(description="Whether auto-tagging is enabled for the customer."),
  customer_currency_code STRING OPTIONS(description="The currency in which the account operates. A subset of the currency codes from the ISO 4217 standard is supported."),
  customer_descriptive_name STRING OPTIONS(description="Optional, non-unique descriptive name of the customer."),
  customer_manager BOOL OPTIONS(description="Whether the customer is a manager."),
  customer_test_account BOOL OPTIONS(description="Whether the customer is a test account."),
  customer_time_zone STRING OPTIONS(description="The local timezone ID of the customer.")
)
PARTITION BY DATE(_PARTITIONTIME);
