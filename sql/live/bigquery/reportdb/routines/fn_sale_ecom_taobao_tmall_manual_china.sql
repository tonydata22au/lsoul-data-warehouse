CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_taobao_tmall_manual_china(number_year_back INT64)
AS
WITH CTE AS (
  SELECT 
      o.o_id AS order_id
      ,oo_id
      --,o.raw_oo_id --items_order_id
      ,o.vn_order_date AS order_date
      --,o.items_status 
      --,items_refund_qty
     -- ,o.status
      ,'Sale Ecommerce' AS order_sources_name
      ,CASE 
        WHEN shop_id = 20209463  THEN 'Taobao'
        WHEN shop_id = 20209689  THEN 'Tmall'
        END AS channel
      ,'TQ Ecommerce' AS sale_channel
      ,CASE 
        WHEN shop_id = 20209463  THEN 'Taobao'
        WHEN shop_id = 20209689  THEN 'Tmall'
        END AS sale_channel_details
      ,buyer_account
      ,platform_site
      ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id --warehouse_id cua Kho Trung Quốc (Back-up)
      ,'Kho Trung Quốc (Back-up)' AS warehouse_name
      ,CASE 
            WHEN items_buyer_paid_amount <= 0 THEN 1
            WHEN TRIM(o.items_status) LIKE 'Cancelled' THEN 1
            WHEN (shop_id = 20209463 AND items_refund_qty > 0) THEN 1
        ELSE 0
        END to_remove_record
      ,o.items_sku_id
      ,o.product_code
      ,o.items_qty
      ,o.items_base_price
      ,o.items_buyer_paid_amount
    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual` AS o
    WHERE 1=1
      AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.order_date, day) between '2026-02-01' and '2026-02-28'
      --AND raw_so_id = '6924076713027337292'
      AND shop_id IN (20209463,20209689)
      ORDER BY channel,order_date
)

  SELECT
  * EXCEPT (items_sku_id,product_code,items_qty,items_buyer_paid_amount,items_base_price,to_remove_record)
  ,COUNT(DISTINCT CASE WHEN to_remove_record = 0 THEN order_id END) AS total_orders
  ,COUNT(DISTINCT CASE WHEN LEFT(items_sku_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') AND to_remove_record = 0 THEN product_code END) AS total_products
  ,SUM(CASE WHEN LEFT(items_sku_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') AND to_remove_record = 0 THEN items_qty ELSE 0 END) AS total_units_sold
  ,SUM(items_base_price) AS sale_revenue_cn_gmv
  ,SUM(items_buyer_paid_amount)  AS revenue_cn_gmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_base_price ELSE 0 END) sale_revenue_cn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_buyer_paid_amount ELSE 0 END) revenue_cn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_base_price * 3800 ELSE 0 END) sale_revenue_vn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_buyer_paid_amount * 3800 ELSE 0 END) revenue_vn --nmv
  FROM CTE
  GROUP BY 1, 2, 3,4,5, 6,7,8,9,10,11
  ORDER BY 1 DESC, 2;
