CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_core_order_item_insert`()
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the data from stg_order -> core_order_item
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_order_item_insert`() --today date
*/

DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_order`);
   DECLARE data_insert_from_date DATE DEFAULT
                                            (SELECT MIN(DATE(inserted_at))
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
                                              WHERE DATE(proc_date) = data_proc_date);

 IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_order_item` WHERE order_id IN (SELECT DISTINCT order_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_order_item`
  (
  order_item_id,
  order_date,
  updated_at,
  order_id,
  system_id,
  product_id,
  product_name,
  variation_id,
  cart_quantity,
  is_discount_percent,
  unit_discount,
  item_total_discount,
  line_total,
  retail_price,
  sales_revenue,
  original_retail_price,
  last_import_price,
  average_price,
  quantity_ordered,
  quantity_returned,
  quantity_returning,
  return_count,
  exchange_count,
  is_wholesale,
  is_one_time_product,
  warehouse_id,
  warehouse_name
  )
  SELECT
  order_item_id,
  inserted_at AS order_date,
  MAX(updated_at) AS updated_at,
  order_id,
  system_id,
  product_id,
  product_name,
  variation_id,
  cart_quantity,
  is_discount_percent,
  unit_discount,
  item_total_discount,
  exact_price AS line_total,
  retail_price,
  retail_price * cart_quantity AS sales_revenue,
  original_retail_price,
  last_import_price,
  average_price,
  quantity_ordered,
  quantity_returned,
  quantity_returning,
  return_count,
  exchange_count,
  is_wholesale,
  is_one_time_product,
  warehouse_id,
  warehouse_name
  FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  order_item_id,
  order_date,
  order_id,
  system_id,
  product_id,
  product_name,
  variation_id,
  cart_quantity,
  is_discount_percent,
  unit_discount,
  item_total_discount,
  line_total,
  retail_price,
  sales_revenue,
  original_retail_price,
  last_import_price,
  average_price,
  quantity_ordered,
  quantity_returned,
  quantity_returning,
  return_count,
  exchange_count,
  is_wholesale,
  is_one_time_product,
  warehouse_id,
  warehouse_name;

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'core_pancake'
            ,'core_order_item'
            ,1
            ,1
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_core_order_item_insert'
            ,'core_pancake'
            ,'marine-cycle-484213-b4.core_pancake.core_order_item'
            ,'marine-cycle-484213-b4.core_pancake.sp_core_order_item_insert'
          );

  ELSE 

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'core_pancake'
            ,'core_order_item'
            ,0
            ,0
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_core_order_item_insert'
            ,'core_pancake'
            ,'marine-cycle-484213-b4.core_pancake.core_order_item'
            ,'marine-cycle-484213-b4.core_pancake.sp_core_order_item_insert'
          );
  END IF;
END;