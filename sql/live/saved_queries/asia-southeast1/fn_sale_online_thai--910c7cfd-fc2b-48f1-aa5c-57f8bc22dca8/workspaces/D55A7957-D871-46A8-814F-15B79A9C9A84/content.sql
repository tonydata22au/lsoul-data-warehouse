CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(
  i_number_year_back INT64 -- number of years back from current year
  ,i_type  INT64 --0: Base order by datetime
)
AS
( 
--Sale Online Thailand
--SELECT * EXCEPT(variation_code,product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name) FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(0,0) ORDER BY 1 DESC
--SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(0,1) ORDER BY 1 DESC
--SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_thai_v2`(0,3) ORDER BY 1 DESC
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
      o.inserted_at AS order_date,
       IF(IS_NAN(SAFE_CAST(o.external_order_id AS FLOAT64)) OR o.external_order_id IS NULL, o.order_number, o.external_order_id) AS order_id,      
      o.status AS status_name,
      'Sale Online' AS level_1,
      'VN Online' AS level_2, --Sale Online in Thailand is in the VN Online for tracking Sale Online'target
      CASE 
        WHEN UPPER(TRIM(channel)) LIKE '%ONLINE%' THEN 'Website'
        END AS level_3,
      CAST(customer_phone_no AS STRING) AS customer_id,

      --PRODUCT
      p.product_code,
      oi.product_name,
      v.variation_display_id AS variation_code,
      v.variation_attributes,
      p.product_launch_date,
      SAFE_DIVIDE(oi.original_price,IF(oi.effective_qty = 0,1,oi.effective_qty)) AS retail_price,
      CASE WHEN LEFT(variation_display_id,2) IN ('TG','HT','HN','HH','TD') THEN 1 ELSE 0 END AS to_remove_sku,
      is_sale_end,

      --WAREHOUSE
      '878504e9-fb75-4870-8504-b2ecdbc097ba' AS warehouse_id,
      'Kho Thái (Back-up)' AS warehouse_name,

      --SALE
      oi.original_price AS sales_revenue_thai_gmv,
      oi.discount_seller AS discount,
      oi.discount_platform AS ecom_voucher,
      oi.adjusted_total,
      oi.original_price - oi.discount_seller AS revenue_thai_gmv,
      CASE WHEN LEFT(oi.product_sku,2) NOT IN ('TG','HT','HN','HH','TD') THEN oi.effective_qty ELSE 0  END AS item_qty,

       --ORDER DETAILS
       CASE
            WHEN status IN ('cancelled','returned') THEN 1
            --WHEN LEFT(variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN 1
            ELSE 0
      END to_remove_record

    FROM `marine-cycle-484213-b4.surfosm.core_surfosm_order` AS o
    JOIN `marine-cycle-484213-b4.surfosm.core_surfosm_order_item` AS oi ON o.order_number = oi.order_number
    LEFT JOIN dim_product AS p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.product_sku = v.variation_display_id
    WHERE 1=1
      AND UPPER(TRIM(channel)) LIKE '%ONLINE%' 
)
,core AS (
    SELECT
    * EXCEPT (item_qty,discount,ecom_voucher,adjusted_total)
    ,CASE WHEN to_remove_record = 0 THEN item_qty ELSE 0 END AS item_qty
    ,CASE WHEN to_remove_record = 0 THEN sales_revenue_thai_gmv ELSE 0 END AS sales_revenue_thai --nmv
    ,CASE WHEN to_remove_record = 0 THEN adjusted_total - discount ELSE 0 END AS revenue_thai
    ,CASE WHEN to_remove_record = 0 THEN discount ELSE 0 END AS discount
    ,CASE WHEN to_remove_record = 0 THEN ecom_voucher ELSE 0 END AS ecom_voucher
    FROM stage
) 
  --When i_type = 0, the data is grouped by order_date, and the grain is at level 3.
  SELECT
  * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_thai_gmv,sales_revenue_thai,revenue_thai,discount,ecom_voucher,revenue_thai_gmv,item_qty,to_remove_record),
  '' AS variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price,''  warehouse_id,'' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue_thai_gmv) AS sales_revenue_thai_gmv,
  SUM(revenue_thai_gmv) AS revenue_thai_gmv,
  SUM(discount) AS discount,
  SUM(ecom_voucher) AS ecom_voucher,
  SUM(sales_revenue_thai) AS sales_revenue_thai, --nmv
  SUM(revenue_thai) AS revenue_thai, --nmv
  SUM(sales_revenue_thai * 800) AS sales_revenue_vn, --nmv
  SUM(revenue_thai * 800) AS revenue_vn --nmv   
  FROM core
  WHERE 1=1
  AND i_type = 0
  AND to_remove_record = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  --AND order_id = 'REDACTED_EXAMPLE'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL

    --When i_type = 1, the data is grouped by level_3, and the grain is at variation_code.
  SELECT
  * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_thai_gmv,sales_revenue_thai,revenue_thai,discount,ecom_voucher,revenue_thai_gmv,item_qty,to_remove_record),
  variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price,''  warehouse_id,'' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue_thai_gmv) AS sales_revenue_thai_gmv,
  SUM(revenue_thai_gmv) AS revenue_thai_gmv,
  SUM(discount) AS discount,
  SUM(ecom_voucher) AS ecom_voucher,
  SUM(sales_revenue_thai) AS sales_revenue_thai, --nmv
  SUM(revenue_thai) AS revenue_thai, --nmv
  SUM(sales_revenue_thai * 800) AS sales_revenue_vn, --nmv
  SUM(revenue_thai * 800) AS revenue_vn --nmv   
  FROM core
  WHERE 1=1
  AND i_type = 1
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  --AND order_id = 'REDACTED_EXAMPLE'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL

    --When i_type = 1, the data is grouped by level_3, and the grain is at variation_code.
  SELECT
  * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_thai_gmv,sales_revenue_thai,revenue_thai,discount,ecom_voucher,revenue_thai_gmv,item_qty,to_remove_record),
  variation_code,
  product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue_thai_gmv) AS sales_revenue_thai_gmv,
  SUM(revenue_thai_gmv) AS revenue_thai_gmv,
  SUM(discount) AS discount,
  SUM(ecom_voucher) AS ecom_voucher,
  SUM(sales_revenue_thai) AS sales_revenue_thai, --nmv
  SUM(revenue_thai) AS revenue_thai, --nmv
  SUM(sales_revenue_thai * 800) AS sales_revenue_vn, --nmv
  SUM(revenue_thai * 800) AS revenue_vn --nmv   
  FROM core
  WHERE 1=1
  AND i_type = 3
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  --AND order_id = 'REDACTED_EXAMPLE'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9,10,11,12,13,14,15

  ORDER BY 1 DESC, 2 

)
