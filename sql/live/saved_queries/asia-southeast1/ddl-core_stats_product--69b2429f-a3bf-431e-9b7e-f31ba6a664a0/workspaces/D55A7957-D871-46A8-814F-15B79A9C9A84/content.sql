--drop table `marine-cycle-484213-b4.core_pancake.core_stats_product`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_stats_product`
PARTITION BY DATE(inserted_at)
CLUSTER BY  product_id, product_custom_id, product_display_id
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
TIMESTAMP_TRUNC(proc_date, DAY)  AS inserted_at,
product_id,
REGEXP_EXTRACT(product_custom_id, r'^([^-]+)') AS product_code,
product_custom_id,
product_name,
total_import,
total_export,
total_import_value,
total_export_value,
product_display_id,
product_inserted_at,
begin_inventory,
end_inventory,
begin_inventory_value,
end_inventory_value,
purchase_import,
return_import,
stocktaking_import,
transfer_import,
purchase_export,
transfer_export,
sell_export,
stocktaking_export

FROM `marine-cycle-484213-b4.stg_pancake.stg_stats_product`
WHERE proc_date >= "2019-01-01"
