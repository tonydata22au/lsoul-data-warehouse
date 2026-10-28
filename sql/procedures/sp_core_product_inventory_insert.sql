CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.core_pancake.sp_core_product_inventory_insert(IN i_inserted_at_date STRING)
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the data from stg_product_inventory_increment_by_date -> core_product_inventory_increment_by_date
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_product_inventory_insert`('') --today date
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_product_inventory_insert`('2026-02-08') --specify the date
*/
DECLARE converted_date DATE DEFAULT 
    CASE 
      WHEN i_inserted_at_date IS NULL OR i_inserted_at_date = '' THEN CURRENT_DATE()
      ELSE PARSE_DATE('%Y-%m-%d', i_inserted_at_date)
    END;

INSERT INTO `marine-cycle-484213-b4.core_pancake.core_product_inventory_increment_by_date`
(
proc_date,
inserted_at, 
stats_id,
product_id,
product_code,
product_custom_id,
product_display_id,
product_creation_date,
product_name,
begin_inventory,
begin_inventory_value,
end_inventory,
end_inventory_value,
purchase_import,
return_import,
stocktaking_import,
transfer_import,
total_import,
total_import_value,
purchase_export,
transfer_export,
sell_export,
stocktaking_export,
total_export,
total_export_value
)
SELECT DISTINCT
proc_date,
DATE(inserted_at) AS inserted_at,
stats_id,
product_id,
REGEXP_EXTRACT(product_custom_id, r'^([^-]+)') AS product_code,
product_custom_id,
product_display_id,
product_inserted_at AS product_creation_date,
product_name,
begin_inventory,
begin_inventory_value,
end_inventory,
end_inventory_value,
purchase_import,
return_import,
stocktaking_import,
transfer_import,
total_import,
total_import_value,
purchase_export,
transfer_export,
sell_export,
stocktaking_export,
total_export,
total_export_value
FROM `marine-cycle-484213-b4.stg_pancake.stg_stats_product_increment_by_date`
WHERE TIMESTAMP_TRUNC(proc_date, DAY) = TIMESTAMP(converted_date);
END;
