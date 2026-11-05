config {
  type:"incremental",
  name:"stg_orders_returned",
  dataset:"stg_pancake",
  dependencyTargets:[{
    name:"raw_orders_returned"
  }],
}
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
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) =  TIMESTAMP(CURRENT_DATE())