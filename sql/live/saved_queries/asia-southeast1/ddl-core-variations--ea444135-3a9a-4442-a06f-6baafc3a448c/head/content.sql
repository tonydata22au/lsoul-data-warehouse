--DROP TABLE `marine-cycle-484213-b4.core_pancake.core_variations`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_variations`
PARTITION BY DATE(updated_at)
CLUSTER BY variation_id, inserted_at, variation_display_id
AS
SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  product_id,
  REGEXP_EXTRACT(variation_display_id, r'^([^-]+)') AS product_code, 
  variation_id, 
  variation_display_id,
  CASE 
      WHEN size_value NOT LIKE '' AND  color_value NOT LIKE '' THEN CONCAT(size_value,' - ',color_value) 
      WHEN size_value LIKE '' AND  color_value NOT LIKE '' THEN color_value
      WHEN size_value NOT LIKE '' AND  color_value  LIKE '' THEN size_value
      ELSE NULL
  END variation_attributes, 
  size_name,
  size_value,
  color_name,
  color_value,
  retail_price,
  retail_price_after_discount,
  last_imported_price,
  total_purchase_price,
  price_at_counter,
  wholesale_price,
  remain_quantity,
  is_hidden, 
  is_locked,
  is_removed,
  is_sell_negative,
  is_composite
FROM `marine-cycle-484213-b4.stg_pancake.stg_variations`
WHERE proc_date >= "2026-01-01"
GROUP BY
  inserted_at,
  product_id,
  variation_id, 
  variation_display_id, 
  size_name,
  size_value,
  color_name,
  color_value,
  retail_price,
  retail_price_after_discount,
  last_imported_price,
  total_purchase_price,
  price_at_counter,
  wholesale_price,
  remain_quantity,
  is_hidden, 
  is_locked,
  is_removed,
  is_sell_negative,
  is_composite;