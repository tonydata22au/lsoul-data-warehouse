CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_AssetGroupListingGroupFilter_6757483582`
(
  asset_group_listing_group_filter_case_value_product_category_category_id STRING OPTIONS(description="ID of the product category. This ID is equivalent to the google_product_category ID as described in this article: https://support.google.com/merchants/answer/6324436"),
  asset_group_listing_group_filter_id STRING OPTIONS(description="The ID of the ListingGroupFilter."),
  asset_group_listing_group_filter_asset_group STRING OPTIONS(description="The asset group which this asset group listing group filter is part of."),
  asset_group_listing_group_filter_case_value_product_brand_value STRING OPTIONS(description="String value of the product brand."),
  asset_group_listing_group_filter_case_value_product_category_level STRING OPTIONS(description="Indicates the level of the category in the taxonomy."),
  asset_group_listing_group_filter_case_value_product_channel_channel STRING OPTIONS(description="Value of the locality."),
  asset_group_listing_group_filter_case_value_product_condition_condition STRING OPTIONS(description="Value of the condition."),
  asset_group_listing_group_filter_case_value_product_custom_attribute_index STRING OPTIONS(description="Indicates the index of the custom attribute."),
  asset_group_listing_group_filter_case_value_product_custom_attribute_value STRING OPTIONS(description="String value of the product custom attribute."),
  asset_group_listing_group_filter_case_value_product_item_id_value STRING OPTIONS(description="Value of the id."),
  asset_group_listing_group_filter_case_value_product_type_level STRING OPTIONS(description="Level of the type."),
  asset_group_listing_group_filter_case_value_product_type_value STRING OPTIONS(description="Value of the type."),
  asset_group_listing_group_filter_listing_source STRING OPTIONS(description="The source of listings filtered by this listing group filter."),
  asset_group_listing_group_filter_parent_listing_group_filter STRING OPTIONS(description="Resource name of the parent listing group subdivision. Null for the root listing group filter node."),
  asset_group_listing_group_filter_type STRING OPTIONS(description="Type of a listing group filter node.")
)
PARTITION BY DATE(_PARTITIONTIME);
