CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_item_insert`()
BEGIN
/*
Author: Toan Pham
Date: 02/05/2026
Comment: This store procedure is to insert the data from stg_surfosm_order -> core_surfosm_order_item
Run syntax: 
  CALL `marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_item_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(parameter_date) 
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(parameter_date)
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.surfosm.core_surfosm_order_item` WHERE parameter_date >= data_insert_from_date;
    
  INSERT INTO `marine-cycle-484213-b4.surfosm.core_surfosm_order_item`
  (
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  product_sku,
  product_code,
  product_launch_date,
  product_name,
  product_qty,
  cancelled_qty,
  returned_qty,
  effective_qty,
  adjusted_total,
  selling_price,
  original_price,
  paid_price,
  discount_platform,
  discount_seller,
  shipped_product_sku,
  shipped_product_code,
  shipped_product_name,
  shipped_qty,
  shipped_cancelled_qty,
  shipped_returned_qty,
  shipped_effective_qty,
  shipped_adjusted_total,
  shipped_cost,
  shipped_product_selling_price
  )
  SELECT DISTINCT
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  IFNULL(order_items_item_sku,order_items_item_code) AS product_sku,
  REGEXP_EXTRACT(order_items_item_code, r'^([^-]+)') AS product_code,
   DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(order_items_item_code, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(order_items_item_code, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
  order_items_item_name AS product_name,
  order_items_item_qty AS product_qty,
  order_items_item_cancelled_qty AS cancelled_qty, 
  order_items_item_returned_qty AS returned_qty,
  order_items_item_effective_qty AS effective_qty, 
  order_items_item_adjusted_total AS adjusted_total,
  order_items_selling_price * order_items_item_qty AS selling_price,
  order_items_original_price * order_items_item_qty AS original_price,
  order_items_paid_price * order_items_item_qty AS paid_price,
  order_items_discount_platform  AS discount_platform,
  order_items_discount_seller AS discount_seller,
  IFNULL(order_items_shipped_item_sku,order_items_shipped_item_code) AS shipped_product_sku,
  REGEXP_EXTRACT(order_items_shipped_item_code, r'^([^-]+)') AS shipped_product_code,
  order_items_shipped_item_name AS shipped_product_name,
  order_items_shipped_item_qty AS shipped_qty,
  order_items_shipped_item_cancelled_qty AS shipped_cancelled_qty,
  order_items_shipped_item_returned_qty AS shipped_returned_qty,
  order_items_shipped_item_effective_qty AS shipped_effective_qty, 
  order_items_shipped_item_adjusted_total AS shipped_adjusted_total,
  order_items_shipped_item_cost AS shipped_cost,
  order_items_shipped_item_selling AS shipped_product_selling_price
  FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'parameter_date'
  ,'parameter_date'
  ,30
  ,'surfosm'
  ,'core_surfosm_order_item'
  ,'surfosm'
  ,'sp_surfosm_core_order_item_insert'  
  ,'marine-cycle-484213-b4.surfosm.stg_surfosm_order'
  ,'marine-cycle-484213-b4.surfosm.core_surfosm_order_item'
  ,null
  ,'marine-cycle-484213-b4.surfosm.raw_surfosm_order'
  );

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'parameter_date'
  ,'parameter_date'
  ,30
  ,'surfosm'
  ,'core_surfosm_order_item'
  ,'surfosm'
  ,'sp_surfosm_core_order_item_insert'  
  ,'marine-cycle-484213-b4.surfosm.stg_surfosm_order'
  ,'marine-cycle-484213-b4.surfosm.core_surfosm_order_item'
  ,null
  ,'marine-cycle-484213-b4.surfosm.raw_surfosm_order'
  );

  END IF;
END;