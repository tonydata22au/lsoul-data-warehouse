--truncate table `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`
AS
SELECT
TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at))  AS inserted_at, 
SAFE_CAST(display_id AS INT64) AS display_id, 
SAFE_CAST(status AS INT64) AS status, 
bill_full_name, 
customer_id, 
DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', updated_at)) AS updated_at, 
creator_id, 
SAFE_CAST(order_id AS INT64) AS order_id, 
order_to_returned_id
FROM `marine-cycle-484213-b4.raw_pancake.raw_orders_returned`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2020-03-01")

