--Drop table `marine-cycle-484213-b4.stg_pancake.stg_product`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_product`
PARTITION BY DATE(proc_date)
AS
SELECT DISTINCT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at))  AS inserted_at,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', updated_at))  AS updated_at,
  product_id,
  product_display_id AS display_id, 
  TRIM(product_name) AS product_name, 
  product_attributes, 
  product_supplier_product_ids AS supplier_product_ids,
  product_tags
FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-01-01")