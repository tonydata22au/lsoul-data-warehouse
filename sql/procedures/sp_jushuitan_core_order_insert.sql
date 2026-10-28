CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.jushuitan.sp_jushuitan_core_order_insert()
BEGIN
/*
Author: Toan Pham
Date: 09/05/2026
Comment: This store procedure is to insert the data from stg_jushuitan_order -> core_jushuitan_order
Run syntax: 
  CALL `marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(DATE(inserted_at))
                                              FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` WHERE o_id IN (SELECT DISTINCT o_id
                                                                                FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.jushuitan.core_jushuitan_order`
  (
  ts,
inserted_at,
o_id,
order_date,
vn_order_date,
so_id,
raw_so_id,
merge_so_id,
raw_so_ids,
type,
status,
shop_status,
order_from,
is_merge,
is_split,
as_id,
tag,
shop_id,
shop_name,
shop_site,
buyer_id,
creator_name,
buyer_message,
labels,
node,
remark,
question_desc,
created,
pay_date,
plan_delivery_date,
send_date,
sign_time,
end_time,
lc_id,
logistics_company,
l_id,
wms_co_id,
receiver_state,
receiver_city,
receiver_district,
receiver_town,
receiver_zip,
is_cod,
amount,
pay_amount,
paid_amount,
seller_income_amount,
freight,
f_freight,
platform_free_amount,
pay_free_amount,
referrer_free_amount,
shop_free_amount,
government_free_amount,
service_charge,
currency,
outer_pay_id,
ext_datas,
skus,
discount_rate
)
SELECT
ts,
MAX(inserted_at) AS inserted_at,
o_id,
order_date,
vn_order_date,
so_id,
raw_so_id,
merge_so_id,
raw_so_ids,
type,
status,
shop_status,
order_from,
is_merge,
is_split,
as_id,
tag,
shop_id,
shop_name,
shop_site,
buyer_id,
creator_name,
buyer_message,
labels,
node,
remark,
question_desc,
created,
pay_date,
plan_delivery_date,
send_date,
sign_time,
end_time,
lc_id,
logistics_company,
l_id,
wms_co_id,
receiver_state,
receiver_city,
receiver_district,
receiver_town,
receiver_zip,
is_cod,
amount,
pay_amount,
paid_amount,
seller_income_amount,
freight,
f_freight,
platform_free_amount,
pay_free_amount,
referrer_free_amount,
shop_free_amount,
government_free_amount,
service_charge,
currency,
outer_pay_id,
ext_datas,
skus,
discount_rate
FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
GROUP BY
ts,
order_date,
vn_order_date,
o_id,
so_id,
raw_so_id,
merge_so_id,
raw_so_ids,
type,
status,
shop_status,
order_from,
is_merge,
is_split,
as_id,
tag,
shop_id,
shop_name,
shop_site,
buyer_id,
creator_name,
buyer_message,
labels,
node,
remark,
question_desc,
created,
pay_date,
plan_delivery_date,
send_date,
sign_time,
end_time,
lc_id,
logistics_company,
l_id,
wms_co_id,
receiver_state,
receiver_city,
receiver_district,
receiver_town,
receiver_zip,
is_cod,
amount,
pay_amount,
paid_amount,
seller_income_amount,
freight,
f_freight,
platform_free_amount,
pay_free_amount,
referrer_free_amount,
shop_free_amount,
government_free_amount,
service_charge,
currency,
outer_pay_id,
ext_datas,
skus,
discount_rate;
  
  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'jushuitan'
            ,'core_jushuitan_order'
            ,1
            ,1
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_jushuitan_core_order_insert'
            ,'jushuitan'
            ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_order'
            ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_insert'
          );

  ELSE 

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'jushuitan'
            ,'core_jushuitan_order'
            ,0
            ,0
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_jushuitan_core_order_insert'
            ,'jushuitan'
            ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_order'
            ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_insert'
          );
  END IF;
END;
