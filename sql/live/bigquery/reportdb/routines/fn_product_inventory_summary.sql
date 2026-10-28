CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_product_inventory_summary(i_type INT64, i_number_year_back INT64, i_days_range INT64, i_FromDate DATE, i_ToDate DATE)
AS
WITH cte_01 AS (
SELECT
v.updated_at
,v.product_code
,v.variation_display_id
,variation_attributes
,DATE_DIFF(CURRENT_DATE(), product_launch_date, DAY) AS product_days_since_launch
,CASE WHEN DATE_DIFF(CURRENT_DATE(), product_launch_date, DAY) < i_days_range THEN DATE_DIFF(CURRENT_DATE(), product_launch_date, DAY) + 1 ELSE i_days_range END AS days_range
,CASE WHEN TRIM(UPPER(p.product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END is_sale_end
,product_name
,product_launch_date
,v.retail_price
,vw.warehouse_id
,IFNULL(vw.actual_remain_qty,0) AS actual_remain_qty 
FROM `marine-cycle-484213-b4.core_pancake.core_variations` v
JOIN `marine-cycle-484213-b4.core_pancake.core_product` p ON v.product_id = p.raw_product_id
LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variation_warehouses` vw ON v.variation_id = vw.variation_id 
WHERE 1=1
ORDER BY 3, 1 DESC
)

--order_product_inventory_daily 
,cte_02 AS (
  SELECT
  period_date
  ,variation_code
  ,product_name
  ,retail_price
  ,warehouse_id
  ,CASE 
      WHEN DATE(period_date) >= '2026-06-01' AND warehouse_id =  '76be7836-6dc5-4b1c-9e48-b18e43127453' --Kho Trung Quoc (Back-up)
      THEN 'Kho Trung Quốc (nguồn Pancake + Dianplus + Jushuitan)' 
      WHEN DATE(period_date) >= '2026-02-13' AND warehouse_id = '878504e9-fb75-4870-8504-b2ecdbc097ba' --Kho Thai Lan (Back-up)
      THEN 'Kho Thái Lan (nguồn Pancake + Scale-Up Fulfilment)' 
      ELSE warehouse_name END AS warehouse_name
  ,sl_nhap_moi_tu_sx
  ,sl_nhap_kho
  ,SUM(sl_ton_kho) OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS sl_ton_kho  
  ,order_sources_name
  ,sale_channel
  ,sale_channel_details
  ,order_year
  ,sales_revenue
  ,revenue
  ,units_sold
  FROM
  (
  SELECT
  DATE(i.inserted_at) AS period_date
  ,variation_code
  ,CAST(NULL AS STRING) AS product_name
  ,CAST(NULL AS FLOAT64) AS retail_price
  ,i.warehouse_id
  ,i.warehouse_name
  ,sl_nhap_moi_tu_sx
  ,sl_nhap_kho
  ,CASE
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at)) <> sl_ton_kho
    THEN sl_ton_kho - LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at))
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code, i.warehouse_id ORDER BY DATE(i.inserted_at)) IS NULL
    THEN sl_ton_kho
    ELSE 0 END AS sl_ton_kho
  ,CAST(NULL AS STRING) AS order_sources_name
  ,CAST(NULL AS STRING) AS sale_channel
  ,CAST(NULL AS STRING) AS sale_channel_details
  ,CAST(NULL AS INT64) AS order_year
  ,0 AS sales_revenue
  ,0 AS revenue
  ,0 AS units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_product_variations_warehouse_summary`(1,i_number_year_back,'') i
  WHERE 1=1
  AND i.warehouse_type NOT IN ('NONE','M')

  UNION ALL

  SELECT
  i.updated_at
  ,variation_code
  ,product_name
  ,retail_price
  ,pancake_warehouse_id
  ,i.warehouse_name
  ,0 AS sl_nhap_moi_tu_sx
  ,sl_nhap_kho AS sl_nhap_kho_china
  ,CASE 
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))  <> sl_ton_kho
    THEN sl_ton_kho - LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))
    WHEN LAG(sl_ton_kho) OVER (PARTITION BY variation_code ORDER BY DATE(i.updated_at))  IS NULL
    THEN sl_ton_kho
    ELSE 0 END AS sl_ton_kho
  ,CAST(NULL AS STRING) AS order_sources_name
  ,CAST(NULL AS STRING) AS sale_channel
  ,CAST(NULL AS STRING) AS sale_channel_details
  ,CAST(NULL AS INT64) AS order_year
  ,0 AS sales_revenue
  ,0 AS revenue
  ,0 AS units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_china_product_inventory`(0,i_number_year_back) i


  UNION ALL

  SELECT
  updated_at
  ,sku
  ,product_name
  ,retail_price
  ,warehouse_id
  ,warehouse_name
  ,0 AS sl_nhap_moi_tu_sx
  ,sl_nhap_kho AS sl_nhap_kho_thai
  ,CASE 
    WHEN LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))  <> stock_on_hand
    THEN stock_on_hand - LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))
    WHEN LAG(stock_on_hand) OVER (PARTITION BY sku ORDER BY DATE(updated_at))  IS NULL
    THEN stock_on_hand
    ELSE 0 END AS sl_ton_kho
  ,CAST(NULL AS STRING) AS order_sources_name
  ,CAST(NULL AS STRING) AS sale_channel
  ,CAST(NULL AS STRING) AS sale_channel_details
  ,CAST(NULL AS INT64) AS order_year
  ,0 AS sales_revenue
  ,0 AS revenue
  ,0 AS units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_thailand_product_inventory`(0,i_number_year_back)
  
  UNION ALL

  SELECT
  DATE(o.period_date) AS period_date
  ,variation_code
  ,product_name
  ,retail_price
  ,warehouse_id
  ,warehouse_name
  ,0 AS sl_nhap_moi_tu_sx
  ,0 AS sl_nhap_kho
  ,0 AS sl_ton_kho
  ,o.level_1
  ,o.level_2
  ,o.level_3
  ,CAST(NULL AS INT64)
  ,o.sales_revenue_vn
  ,o.revenue_vn
  ,units_sold
  FROM `marine-cycle-484213-b4.reportdb.fn_order_sku_warehouse_master`(i_number_year_back,0) o
  )
  WHERE 1=1
  AND LEFT(variation_code,2) NOT IN ('TG','HT','HN','HH','TD')
  AND (retail_price <> 0 OR retail_price IS NULL)
) 

,cte_03 AS (
SELECT
period_date
,variation_code
,MAX(product_name) AS product_name
,MAX(retail_price) AS retail_price
,warehouse_id
,warehouse_name
,MAX(order_sources_name) AS order_sources_name
,MAX(sale_channel) AS sale_channel
,MAX(sale_channel_details) AS sale_channel_details
,MAX(order_year) AS order_year
,SUM(sl_nhap_moi_tu_sx ) AS sl_nhap_moi_tu_sx
,SUM(sl_nhap_kho) AS sl_nhap_kho
,MAX(sl_ton_kho) AS sl_ton_kho
,SUM(sales_revenue) AS sales_revenue
,SUM(revenue) AS revenue
,SUM(units_sold) AS units_sold
FROM cte_02
WHERE 1=1
GROUP BY 1,2,5,6
ORDER BY 1,warehouse_id
)

,cte_04 AS (
  SELECT DISTINCT
    period_date,
    v.product_code,
    variation_code,
    v.variation_attributes,
    v.product_days_since_launch,
    v.days_range,
    v.is_sale_end,
    IFNULL(i.product_name, v.product_name) AS product_name,
    IFNULL(i.retail_price, v.retail_price) AS retail_price,
    i.warehouse_id,
    i.warehouse_name,
    sl_nhap_moi_tu_sx,
    sl_nhap_kho,
    CASE 
                WHEN DATE(period_date) < '2026-06-01' AND i.warehouse_id IN ('76be7836-6dc5-4b1c-9e48-b18e43127453') AND sl_nhap_kho < 0 --Kho Trung Quốc (Back-up)
                THEN sl_nhap_kho * -1 + IFNULL(sl_ton_kho,vw.actual_remain_qty) - units_sold
                WHEN DATE(period_date) < '2026-06-01' AND i.warehouse_id IN ('76be7836-6dc5-4b1c-9e48-b18e43127453') 
                THEN IFNULL(sl_ton_kho,v.actual_remain_qty) - units_sold
                ELSE IFNULL(sl_ton_kho,v.actual_remain_qty)
    END AS sl_ton_kho,
    order_sources_name,
    sale_channel,
    sale_channel_details,
    order_year,
    sales_revenue,
    revenue,
    units_sold

FROM cte_03 i
LEFT JOIN cte_01 v ON i.variation_code = v.variation_display_id 
LEFT JOIN cte_01 vw ON i.variation_code = vw.variation_display_id  AND i.warehouse_id = vw.warehouse_id
WHERE 1=1
AND (i_FromDate is null OR period_date >= i_FromDate)
AND (i_ToDate is null OR period_date <= i_ToDate)
)


,cte_05 AS (
  SELECT
  MAX(period_date) OVER (PARTITION BY variation_code,period_id ORDER BY period_id ) AS latest_period_date
  ,*
  FROM
  (
  SELECT DISTINCT
    period_date,
    ROW_NUMBER() OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date DESC) AS period_id,
    product_code,
    variation_code,
    variation_attributes,
    product_days_since_launch,
    days_range,
    is_sale_end,
    product_name,
    retail_price,
    warehouse_id,
    warehouse_name,
    sl_nhap_moi_tu_sx,
    sl_nhap_kho,
    CASE WHEN IFNULL(sl_ton_kho,IFNULL(LAG(sl_ton_kho) OVER (PARTITION BY variation_code, warehouse_id ORDER BY period_date,0),0)) < 0 THEN 0 
        ELSE IFNULL(sl_ton_kho,IFNULL(LAG(sl_ton_kho) OVER (PARTITION BY variation_code, warehouse_id ORDER BY period_date,0),0))
    END AS sl_ton_kho,           
    order_sources_name,
    sale_channel,
    sale_channel_details,
    order_year,
    sales_revenue,
    revenue,
    units_sold
  FROM cte_04
  )
)

,cte_05_type_1 AS (
  SELECT
    ROW_NUMBER() OVER (PARTITION BY variation_code ORDER BY period_date DESC) AS inventory_id
    ,*
    FROM 
    (
      SELECT
      latest_period_date AS period_date
      ,product_code
      ,variation_code
      ,variation_attributes
      ,product_days_since_launch
      ,days_range
      ,is_sale_end
      ,MAX(product_name) AS product_name
      ,MAX(retail_price) AS retail_price
      ,MAX(order_sources_name) AS order_sources_name
      ,MAX(sale_channel) AS sale_channel
      ,MAX(sale_channel_details) AS sale_channel_details
      ,MAX(order_year) AS order_year
      ,SUM(sl_nhap_moi_tu_sx ) AS sl_nhap_moi_tu_sx
      ,SUM(sl_nhap_kho) AS sl_nhap_kho
      ,SUM(IFNULL(sl_ton_kho,0)) AS sl_ton_kho
      ,SUM(sales_revenue) AS sales_revenue
      ,SUM(revenue) AS revenue
      ,SUM(units_sold) AS units_sold
      FROM cte_05
      GROUP BY 1,2,3,4,5,6,7
    )
    ORDER BY period_date DESC
)


,cte_06 AS (
SELECT
*
,SUM(reset_stock_flag) OVER (
      PARTITION BY variation_code,warehouse_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS seg_id
,SUM(reset_units_sold_day_range_flag) OVER (
      PARTITION BY variation_code,warehouse_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS unit_sold_day_range_id
,SUM(reset_emty_stock_flag) OVER (
      PARTITION BY variation_code,warehouse_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS emty_stock_id
FROM
(
SELECT  
*
,sl_ton_kho * retail_price AS tong_gia_tri_hang_ton_kho_theo_gia_ban
,CASE WHEN sl_ton_kho = 0 THEN 0 
    ELSE 
    DATE_DIFF(
    period_date,
    LAG(period_date) OVER (
      PARTITION BY variation_code,warehouse_id
      ORDER BY period_date
      )
      , DAY) 
    END AS period_date_gap
,CASE
      WHEN sl_ton_kho <= 0
           AND LAG(sl_ton_kho) OVER (
                 PARTITION BY variation_code,warehouse_id
                 ORDER BY period_date
               ) > 0
      THEN 1
      ELSE 0
    END AS reset_stock_flag
,CASE
      WHEN DATE_DIFF(DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY),period_date,day) > i_days_range
      THEN 1
      ELSE 0
    END AS reset_units_sold_day_range_flag
,CASE 
    WHEN sl_ton_kho > 0
        AND LAG(sl_ton_kho) OVER (
                 PARTITION BY variation_code,warehouse_id
                 ORDER BY period_date
               ) = 0
        THEN 1 ELSE 0 
        END AS reset_emty_stock_flag
,CASE WHEN sl_ton_kho = 0 THEN 
    DATE_DIFF(
    period_date,
    LAG(period_date) OVER (
      PARTITION BY variation_code,warehouse_id
      ORDER BY period_date
      )
      , DAY) 
    ELSE 0
    END AS empty_stock_period_date_gap
FROM cte_05 i 
)
ORDER BY variation_code,warehouse_name, period_date
)

,cte_06_type_1 AS (
SELECT
*
,SUM(reset_stock_flag) OVER (
      PARTITION BY variation_code
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS seg_id
,SUM(reset_units_sold_day_range_flag) OVER (
      PARTITION BY variation_code
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS unit_sold_day_range_id
,SUM(reset_emty_stock_flag) OVER (
      PARTITION BY variation_code
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS emty_stock_id
FROM
(
SELECT  
*
,sl_ton_kho * retail_price AS tong_gia_tri_hang_ton_kho_theo_gia_ban
,CASE WHEN sl_ton_kho = 0 THEN 0 
    ELSE 
    DATE_DIFF(
    period_date,
    LAG(period_date) OVER (
      PARTITION BY variation_code
      ORDER BY period_date
      )
      , DAY) 
    END AS period_date_gap
,CASE
      WHEN sl_ton_kho <= 0
           AND LAG(sl_ton_kho) OVER (
                 PARTITION BY variation_code
                 ORDER BY period_date
               ) > 0
      THEN 1
      ELSE 0
    END AS reset_stock_flag
,CASE
      WHEN DATE_DIFF(DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY),period_date,day) > i_days_range
      THEN 1
      ELSE 0
    END AS reset_units_sold_day_range_flag
,CASE 
    WHEN sl_ton_kho > 0
        AND LAG(sl_ton_kho) OVER (
                 PARTITION BY variation_code
                 ORDER BY period_date
               ) = 0
        THEN 1 ELSE 0 
        END AS reset_emty_stock_flag
,CASE WHEN sl_ton_kho = 0 THEN 
    DATE_DIFF(
    period_date,
    LAG(period_date) OVER (
      PARTITION BY variation_code
      ORDER BY period_date
      )
      , DAY) 
    ELSE 0
    END AS empty_stock_period_date_gap
FROM cte_05_type_1 i 
)
ORDER BY variation_code, period_date

)

,cte_07 AS (
SELECT
    period_date,
    ROW_NUMBER() OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date DESC) AS sort_desc,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date DESC) = 1 THEN 1 ELSE 0 END AS is_latest,
    product_code,
    variation_code,
    variation_attributes,
    product_days_since_launch,
    days_range,
    is_sale_end,
    product_name,
    retail_price,
    warehouse_id,
    warehouse_name,
    sl_nhap_moi_tu_sx,
    sl_nhap_kho,
    sl_ton_kho,
    tong_gia_tri_hang_ton_kho_theo_gia_ban,
    order_sources_name,
    sale_channel,
    sale_channel_details,
    order_year,
    sales_revenue,
    revenue,
    units_sold,
    IFNULL(SUM(period_date_gap) OVER (
      PARTITION BY variation_code,warehouse_id,seg_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS ton_kho_running_days

    ,IFNULL(SUM(empty_stock_period_date_gap) OVER (
      PARTITION BY variation_code,warehouse_id,emty_stock_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS emty_stock_days
    ,IFNULL(SUM(units_sold) OVER (
      PARTITION BY variation_code,warehouse_id,seg_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS units_sold_day_range
    FROM cte_06
    WHERE i_type = 0
)

,cte_07_type1 AS (
  SELECT
    period_date,
    1 AS sort_desc,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY variation_code ORDER BY period_date DESC) = 1 THEN 1 ELSE 0 END AS is_latest,
    product_code,
    variation_code,
    variation_attributes,
    product_days_since_launch,
    days_range,
    is_sale_end,
    product_name,
    retail_price,
    '' AS warehouse_id,
    '' AS warehouse_name,
    sl_nhap_moi_tu_sx,
    sl_nhap_kho,
    sl_ton_kho,
    tong_gia_tri_hang_ton_kho_theo_gia_ban,
    '' AS order_sources_name,
    '' AS sale_channel,
    '' AS sale_channel_details,
    NULL AS order_year,
    SUM(sales_revenue) OVER (PARTITION BY variation_code ORDER BY period_date) AS sales_revenue,
    SUM(revenue) OVER (PARTITION BY variation_code ORDER BY period_date) AS revenue,
    SUM(units_sold) OVER (PARTITION BY variation_code ORDER BY period_date) AS units_sold,
    IFNULL(SUM(period_date_gap) OVER (
      PARTITION BY variation_code,seg_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS ton_kho_running_days

    ,IFNULL(SUM(empty_stock_period_date_gap) OVER (
      PARTITION BY variation_code,emty_stock_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS emty_stock_days
    ,IFNULL(SUM(units_sold) OVER (
      PARTITION BY variation_code,seg_id
      ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      ,0)
      AS units_sold_day_range
    FROM cte_06_type_1
    WHERE i_type = 1
)

--master table
SELECT 
period_date,
sort_desc,
is_latest,
product_code,
variation_code,
variation_attributes,
product_days_since_launch,
days_range,
is_sale_end,
product_name,
retail_price,
warehouse_id,
warehouse_name,
sl_nhap_moi_tu_sx,
sl_nhap_kho,
sl_ton_kho,
tong_gia_tri_hang_ton_kho_theo_gia_ban,  
order_sources_name,
sale_channel,
sale_channel_details,
order_year,
sales_revenue,
revenue,
units_sold,
ton_kho_running_days,
emty_stock_days,
units_sold_day_range,
sl_ton_kho - IFNULL(LAG(sl_ton_kho) OVER (PARTITION BY variation_code,warehouse_id ORDER BY period_date ),sl_ton_kho) AS sl_ton_kho_diff
FROM cte_07 where i_type = 0

UNION ALL
  
  SELECT 
  * 
  ,0 AS sl_ton_kho_diff
  FROM cte_07_type1 where i_type = 1 AND is_latest = 1
  ORDER BY 5,2,warehouse_name;
