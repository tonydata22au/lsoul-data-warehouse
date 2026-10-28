CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_BidGoal_6757483582`
(
  bidding_strategy_id INT64 OPTIONS(description="The ID of the bidding strategy."),
  customer_id INT64 OPTIONS(description="The ID of the customer."),
  bidding_strategy_name STRING OPTIONS(description="The name of the bidding strategy. All bidding strategies within an account must be named distinctly. The length of this string should be between 1 and 255, inclusive, in UTF-8 bytes, (trimmed)."),
  bidding_strategy_status STRING OPTIONS(description="The status of the bidding strategy. This field is read-only."),
  bidding_strategy_target_cpa_cpc_bid_ceiling_micros INT64 OPTIONS(description="Maximum bid limit that can be set by the bid strategy. The limit applies to all keywords managed by the strategy."),
  bidding_strategy_target_cpa_cpc_bid_floor_micros INT64 OPTIONS(description="Minimum bid limit that can be set by the bid strategy. The limit applies to all keywords managed by the strategy."),
  bidding_strategy_target_cpa_target_cpa_micros INT64 OPTIONS(description="Average CPA target. This target should be greater than or equal to minimum billable unit based on the currency for the account."),
  bidding_strategy_target_roas_cpc_bid_ceiling_micros INT64 OPTIONS(description="Maximum bid limit that can be set by the bid strategy. The limit applies to all keywords managed by the strategy."),
  bidding_strategy_target_roas_cpc_bid_floor_micros INT64 OPTIONS(description="Minimum bid limit that can be set by the bid strategy. The limit applies to all keywords managed by the strategy."),
  bidding_strategy_target_roas_target_roas FLOAT64 OPTIONS(description="Required. The desired revenue (based on conversion data) per unit of spend. Value must be between 0.01 and 1000.0, inclusive."),
  bidding_strategy_target_spend_cpc_bid_ceiling_micros INT64 OPTIONS(description="Maximum bid limit that can be set by the bid strategy. The limit applies to all keywords managed by the strategy."),
  bidding_strategy_target_spend_target_spend_micros INT64 OPTIONS(description="The spend target under which to maximize clicks. A TargetSpend bidder will attempt to spend the smaller of this value or the natural throttling spend amount. If not specified, the budget is used as the spend target."),
  bidding_strategy_type STRING OPTIONS(description="The type of the bidding strategy. Create a bidding strategy by setting the bidding scheme. This field is read-only."),
  customer_descriptive_name STRING OPTIONS(description="Optional, non-unique descriptive name of the customer.")
)
PARTITION BY DATE(_PARTITIONTIME);
