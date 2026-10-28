CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_assortment_seg_cont_by_warehouse(i_type INT64, i_exclude_sale_end INT64)
AS
WITH sku_performance AS (
SELECT
d_date
,IFNULL(sp.variation_code,string_field_1) AS sku
,IFNULL(sp.retail_price,SAFE_CAST(string_field_2 AS FLOAT64)) AS gia_ban
,string_field_3 AS chung_loai
,string_field_4 AS nhom_chung_loai
,string_field_5 AS bst
,sp.warehouse_id
,sp.warehouse_name
,CASE WHEN is_latest = 1 THEN COALESCE(sl_ton_kho,0) ELSE 0 END AS sl_ton_kho
,COALESCE(SUM(sp.revenue),0) AS revenue
,COALESCE(SUM(sp.units_sold),0) AS units_sold
,CASE WHEN is_latest = 1 THEN COALESCE(SUM(units_sold_day_range),0) ELSE 0 END AS units_sold_day_range
FROM `marine-cycle-484213-b4.reportdb.report_order_product_inventory_summary` sp 
LEFT JOIN  `marine-cycle-484213-b4.reportdb.product_tree_csv` pt ON pt.string_field_1 = sp.variation_code
WHERE 1=1
AND report_type = 0
AND i_type = 0
AND (pt.string_field_6 NOT LIKE 'none' OR pt.string_field_6  IS NULL)
AND (i_exclude_sale_end = 0 OR (i_exclude_sale_end = 1 AND (TRIM(pt.string_field_6) NOT IN ('','QUA MẪU') OR pt.string_field_6  IS NULL)))
--AND sp.warehouse_name = 'Kho Online'
GROUP BY 1,2,3,4,5,6,7,8,9,is_latest 
ORDER BY 2 

)
,company_totals AS (
SELECT
  COUNT(DISTINCT CASE WHEN sl_ton_kho > 0 THEN sku END) AS global_sku_count
  ,SUM(units_sold) AS global_units_sold
  ,SUM(revenue) AS global_revenue
FROM sku_performance
)

-- =========================================================================
-- REPORT 1: PERFORMANCE BY PRODUCT CATEGORY & WAREHOUSE
-- =========================================================================
SELECT
 IFNULL(nhom_chung_loai,'N/A') AS group_category,
 IFNULL(chung_loai,'N/A') AS product_segment,
 warehouse_name,
 SUM(s.sl_ton_kho) AS sl_ton_kho,
 COUNT(DISTINCT CASE WHEN s.sl_ton_kho > 0 THEN s.sku END) AS sku_count,
 SAFE_DIVIDE(COUNT(DISTINCT s.sku), t.global_sku_count) AS sku_share_pct, --SKU Share (%)
  SUM(s.units_sold) AS units_sold,
  SAFE_DIVIDE(SUM(s.units_sold), t.global_units_sold) AS sales_volume_share_pct,
  SUM(s.revenue) AS total_revenue,
  SAFE_DIVIDE(SUM(s.revenue), t.global_revenue) AS revenue_contribution_pct, --Revenue Contribution (%)
  -- Sell-Through Rate (STR) = Units Sold / Initial Stock Allocated
  SAFE_DIVIDE(SUM(s.units_sold_day_range), SUM(s.sl_ton_kho)) AS sell_through_rate_pct --Sell-Through Rate (STR %)
FROM 
  sku_performance s
CROSS JOIN 
  company_totals t
WHERE i_type = 0
GROUP BY 1,2,3,global_sku_count,global_units_sold,global_revenue;
