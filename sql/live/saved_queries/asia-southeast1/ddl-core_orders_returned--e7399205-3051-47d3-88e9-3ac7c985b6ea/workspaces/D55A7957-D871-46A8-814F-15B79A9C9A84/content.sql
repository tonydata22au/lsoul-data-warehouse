--truncate table `marine-cycle-484213-b4.core_pancake.core_orders_returned`


INSERT INTO `marine-cycle-484213-b4.core_pancake.core_orders_returned`
SELECT
*
,CASE WHEN RANK() OVER (PARTITION BY order_to_returned_id ORDER BY display_id DESC, inserted_at DESC) > 1 THEN 1 ELSE 0 END AS is_duplicate
FROM 
(SELECT DISTINCT
inserted_at, 
display_id, 
status, 
bill_full_name, 
customer_id, 
updated_at, 
creator_id, 
order_id, 
order_to_returned_id
FROM `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`
WHERE  proc_date >=  TIMESTAMP("2020-03-01") AND display_id BETWEEN
AND order_id is not null
)

;

