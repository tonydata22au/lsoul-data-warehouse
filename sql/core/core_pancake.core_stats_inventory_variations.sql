--DROP TABLE `marine-cycle-484213-b4.core_pancake.core_stats_inventory_variations`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_stats_inventory_variations`
PARTITION BY DATE(inserted_at)
CLUSTER BY  product_id, product_custom_id,variation_custom_id, product_name
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
TIMESTAMP_TRUNC(proc_date, DAY)  AS inserted_at,
product_id, 
product_custom_id,
REGEXP_EXTRACT(product_custom_id, r'^([^-]+)') AS product_code, 
product_display_id,
product_name, 
product_inserted_at
variation_id, 
variation_custom_id,
REGEXP_EXTRACT(variation_custom_id, r'^([^-]+)') AS variation_code,  
variation_display_id, 
variation_fields, 
begin_inventory,
begin_inventory_value,
total_import,
total_export,
total_import_value,
total_export_value,
purchase_import,
return_import,
stocktaking_import,
transfer_import,
purchase_export,
transfer_export,
sell_export,
stocktaking_export,
end_inventory,
end_inventory_value
FROM `marine-cycle-484213-b4.stg_pancake.stg_stats_inventory_variations`
WHERE proc_date between "2019-01-01" and "2026-05-24"
