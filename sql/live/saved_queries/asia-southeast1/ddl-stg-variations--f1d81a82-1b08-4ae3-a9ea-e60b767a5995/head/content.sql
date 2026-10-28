--DROP TABLE  `marine-cycle-484213-b4.stg_pancake.stg_variations`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_variations`
PARTITION BY DATE(proc_date)
AS
SELECT DISTINCT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at))  AS inserted_at,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', updated_at))  AS updated_at,
  product_id, 
  variation_id,
  variation_display_id, 
  size_name, 
  size_value, 
  color_name, 
  color_value,
  SAFE_CAST(retail_price AS FLOAT64) AS retail_price,
  SAFE_CAST(retail_price_after_discount AS FLOAT64) AS retail_price_after_discount, 
  SAFE_CAST(last_imported_price AS FLOAT64) AS last_imported_price, 
  SAFE_CAST(total_purchase_price AS FLOAT64) AS total_purchase_price,
  SAFE_CAST(price_at_counter AS FLOAT64) AS price_at_counter,  
  SAFE_CAST(wholesale_price AS FLOAT64) AS wholesale_price, 
  SAFE_CAST(remain_quantity AS INT64) AS remain_quantity, 
  SAFE_CAST(is_hidden AS INT64) AS is_hidden, 
  SAFE_CAST(is_locked AS INT64) AS is_locked,
  SAFE_CAST(is_removed AS INT64) AS is_removed,  
  SAFE_CAST(is_sell_negative AS INT64) AS is_sell_negative,  
  SAFE_CAST(is_composite AS INT64) AS is_composite
FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-01-01")