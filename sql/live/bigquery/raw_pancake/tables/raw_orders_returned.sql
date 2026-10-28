CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_orders_returned`
(
  inserted_at STRING,
  display_id STRING,
  status STRING,
  bill_full_name STRING,
  customer_id STRING,
  updated_at STRING,
  creator_id STRING,
  order_id STRING,
  order_to_returned_id STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
