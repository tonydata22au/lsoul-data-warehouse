CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_taobao_tmall_manual_china_v2(i_number_year_back INT64, i_type INT64)
AS
WITH dim_product AS (
  -- ONE row per product_code. This is the entire fix.
  SELECT
     product_code
    ,ANY_VALUE(product_name)        AS product_name
    ,ANY_VALUE(product_launch_date) AS product_launch_date
    ,MAX(CASE WHEN TRIM(UPPER(product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END) AS is_sale_end
  FROM `marine-cycle-484213-b4.core_pancake.core_product`
  GROUP BY product_code
)
,stage AS (
  SELECT
      o.vn_order_date AS order_date 
      ,CAST(o.o_id AS STRING) AS order_id
      --,oo_id
      --,o.raw_oo_id --items_order_id
      ,IFNULL(o.items_status,'success') AS status_name
      ,'Sale Ecommerce' AS level_1
      ,'TQ Ecommerce' AS level_2
      ,CASE 
        WHEN shop_id = 20209463  THEN 'Taobao'
        WHEN shop_id = 20209689  THEN 'Tmall'
        END AS level_3
      --,platform_site
      ,CAST(buyer_account AS STRING) AS customer_id
      
      --,o.items_sku_id
      ,o.product_code
      ,p.product_name
      ,o.items_sku_id AS variation_code
      ,v.variation_attributes
      ,p.product_launch_date
      ,o.items_base_price AS retail_price          -- NOTE: hardcoded FX 3800 VND/CNY
      ,CASE WHEN LEFT(IFNULL(variation_display_id,items_sku_id),2) IN ('TG','HT','HN','HH','TD') THEN 1 ELSE 0 END AS to_remove_sku
      ,IFNULL(p.is_sale_end, 0) AS is_sale_end

      --WAREHOUSE
      ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id --warehouse_id cua Kho Trung Quốc (Back-up)
      ,'Kho Trung Quốc (Back-up)' AS warehouse_name
     
     --SALE
      ,CASE WHEN LEFT(IFNULL(variation_display_id,items_sku_id),2) NOT IN ('TG','HT','HN','HH','TD') THEN items_qty ELSE 0 END          AS item_qty
      ,IF(IS_NAN(items_base_price), 0, items_base_price)                  AS sales_revenue_cn_gmv
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount)     AS revenue_cn_gmv

      ,CASE 
            WHEN items_buyer_paid_amount <= 0 THEN 1
            WHEN TRIM(o.items_status) LIKE 'Cancelled' THEN 1
            WHEN (shop_id = 20209463 AND items_refund_qty > 0) THEN 1
        ELSE 0
        END AS to_remove_record

    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual` AS o
    LEFT JOIN dim_product p ON o.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON o.items_sku_id = v.variation_display_id
    WHERE 1=1
      AND shop_id IN (20209463,20209689)
)
,core AS (
    SELECT
    * EXCEPT (item_qty)
    ,CASE WHEN to_remove_record = 0 THEN item_qty ELSE 0 END AS item_qty
    ,CASE WHEN to_remove_record = 0 THEN sales_revenue_cn_gmv ELSE 0 END AS sales_revenue_cn --nmv
    ,CASE WHEN to_remove_record = 0 THEN revenue_cn_gmv ELSE 0 END AS revenue_cn --nmv
    FROM stage
)

   --When i_type = 0, the data is grouped by order_date, and the grain is at level 3.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,item_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  '' AS variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price, ''  warehouse_id, '' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core
  WHERE 1=1
  AND i_type = 0
  AND to_remove_record = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL
  
  --When i_type = 1, the data is grouped by level_3, and the grain is at variation_code.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,item_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price, ''  warehouse_id, '' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core   
  WHERE 1=1
  AND i_type = 1
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL
  
  --When i_type = 3, the data is grouped by variation_code, and the grain is at warehouse_id.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,item_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  variation_code,
  product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core   
  WHERE 1=1
  AND i_type = 3
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9,10,11,12,13,14,15;
