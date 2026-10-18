--DROP TABLE `marine-cycle-484213-b4.stg_pancake.stg_customer`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_customer`
PARTITION BY DATE(proc_date)
CLUSTER BY  customer_id
AS
  SELECT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(SAFE.PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at))  AS inserted_at,
  DATETIME(SAFE.PARSE_TIMESTAMP('%Y%m%d%H%M%S', updated_at)) AS  updated_at,
  entry_id,
  customer_id,
  username,
  tags,
  fb_id,
  SAFE_CAST(is_block AS INT64) AS is_block,
  assigned_user_id,
  creator_name,
  creator_id,
  currency,
  SAFE_CAST(order_count AS INT64) AS order_count,
  SAFE_CAST(succeed_order_count AS INT64) AS succeed_order_count,
  SAFE_CAST(returned_order_count AS INT64) AS returned_order_count,
  SAFE_CAST(purchased_amount AS FLOAT64) AS purchased_amount,
  DATETIME(SAFE.PARSE_TIMESTAMP('%Y%m%d%H%M%S', last_order_at )) AS last_order_at,
  SAFE_CAST(REGEXP_REPLACE(order_sources, r"[\[\]']", "") AS INT64) AS order_sources,
  shop_customer_addresses_id,
  shop_customer_addresses_country_code,
  shop_customer_addresses_province_id,
  shop_customer_addresses_commune_id
  FROM `marine-cycle-484213-b4.raw_pancake.raw_customer`
  WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-04-16")