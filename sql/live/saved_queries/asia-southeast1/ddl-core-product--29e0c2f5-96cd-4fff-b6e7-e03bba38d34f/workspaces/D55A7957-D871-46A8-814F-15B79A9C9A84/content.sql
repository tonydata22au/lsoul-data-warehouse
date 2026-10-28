--drop table `marine-cycle-484213-b4.core_pancake.core_product`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_product`
PARTITION BY DATE(updated_at)
CLUSTER BY raw_product_id, display_id, product_name
AS
SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  product_id AS raw_product_id,
  display_id,
  REGEXP_EXTRACT(display_id, r'^([^-]+)') AS product_code,
  product_name,
  DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(display_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(display_id, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
  product_attributes,
  supplier_product_ids,
  product_tags
  FROM `marine-cycle-484213-b4.stg_pancake.stg_product`
  WHERE proc_date >= "2010-01-01"
  GROUP BY
  inserted_at,
  product_id,
  display_id,
  product_name, 
  product_attributes, 
  supplier_product_ids, 
  product_tags;
