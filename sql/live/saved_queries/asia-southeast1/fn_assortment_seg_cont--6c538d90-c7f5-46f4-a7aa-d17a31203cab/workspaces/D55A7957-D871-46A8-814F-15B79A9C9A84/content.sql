CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_assortment_seg_cont`(
  i_type INT64 -- 0: bao cao theo chung loai, 1: bao cao theo BST
  ,i_exclude_sale_end INT64 --0: included, 1: exclude
)
AS
/*
Author: Toan Pham
Date: 29/05/2026
Comment: Assortment Segmentation & Contribution Report

Sell‑through rate (%) = Units sold in period / Units received or opening stock for that period ×100.

A. Segmentation by Product CategoryCo-ord Sets: Pre-styled top-and-bottom combinations (e.g., LSOUL's famous hoodie + mini skirt sets).  Dresses: Bodycon, mini, bubble, and statement occasion dresses.  Corsets & Tops: Signature bustiers, asymmetrical cut-out tops, and cropped hoodies.Bottoms: Pleated mini-skirts, cargo pants, and baggy denim.Accessories & Capsules: Bags, footwear, and experimental runway pieces.  

B. Segmentation by Strategic Role (The Fashion Matrix)Hero / Viral Pieces (Trend-Led): High-margin, ultra-trendy items pushed via celebrity endorsements (e.g., items worn by K-pop or Chinese idols). Characterized by rapid sell-through but shorter lifecycles.Core / Volume Anchors (Basics with a Twist): Repeatable, lower-risk styles that generate steady cash flow (e.g., solid-color pleated mini-skirts or basic black corsets).Statement / Halo Pieces: Limited-edition or high-end couture items used primarily for runway, campaigns, and brand positioning rather than massive sales volume.

TESTING:
SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_assortment_seg_cont`(1,0)   --bao cao theo chung loai

*/
(
WITH sku_performance AS (
SELECT
d_date
,IFNULL(sp.variation_code,string_field_1) AS sku
,IFNULL(sp.retail_price,SAFE_CAST(string_field_2 AS FLOAT64)) AS gia_ban
,string_field_3 AS chung_loai
,string_field_4 AS nhom_chung_loai
,string_field_5 AS bst
,CASE WHEN is_latest = 1 THEN COALESCE(sl_ton_kho,0) ELSE 0 END AS sl_ton_kho
,COALESCE(SUM(sp.revenue),0) AS revenue
,COALESCE(SUM(sp.units_sold),0) AS units_sold
FROM `marine-cycle-484213-b4.reportdb.report_order_product_inventory_summary` sp 
LEFT JOIN  `marine-cycle-484213-b4.reportdb.product_tree_20260824` pt ON pt.string_field_1 = sp.variation_code
WHERE 1=1 
AND report_type = 1
AND i_type = 0
AND (pt.string_field_6 NOT LIKE 'none' OR pt.string_field_6  IS NULL)
AND (i_exclude_sale_end = 0 OR (i_exclude_sale_end = 1 AND TRIM(pt.string_field_6) NOT IN ('','QUA MẪU')))
GROUP BY 1,2,3,4,5,6,7,is_latest

UNION ALL

SELECT
d_date
,IFNULL(sp.variation_code,string_field_1) AS sku
,IFNULL(sp.retail_price,SAFE_CAST(string_field_2 AS FLOAT64)) AS gia_ban
,string_field_3 AS chung_loai
,string_field_4 AS nhom_chung_loai
,string_field_5 AS bst
,CASE WHEN is_latest = 1 THEN COALESCE(sl_ton_kho,0) ELSE 0 END AS sl_ton_kho
,COALESCE(SUM(sp.revenue),0) AS revenue
,COALESCE(SUM(sp.units_sold),0) AS units_sold
FROM `marine-cycle-484213-b4.reportdb.report_order_product_inventory_summary` sp 
LEFT JOIN  `marine-cycle-484213-b4.reportdb.product_tree_20260824` pt ON pt.string_field_1 = sp.variation_code
WHERE 1=1 
AND report_type = 1
AND i_type = 1
AND (pt.string_field_6 NOT LIKE 'none' OR pt.string_field_6  IS NULL)
AND IFNULL(TRIM(string_field_5),'0') NOT IN ('0','KHÁC','')
AND (i_exclude_sale_end = 0 OR (i_exclude_sale_end = 1 AND TRIM(pt.string_field_6) NOT IN ('','QUA MẪU')))
GROUP BY 1,2,3,4,5,6,7

)
,company_totals AS (
SELECT
  COUNT(DISTINCT sku) AS global_sku_count
  ,SUM(units_sold) AS global_units_sold
  ,SUM(revenue) AS global_revenue
FROM sku_performance
)

-- =========================================================================
-- REPORT 1: PERFORMANCE BY PRODUCT CATEGORY
-- =========================================================================
SELECT
 IFNULL(nhom_chung_loai,'N/A') AS group_category,
 IFNULL(chung_loai,'N/A') AS product_segment,
 COUNT(DISTINCT s.sku) AS sku_count,
  SAFE_DIVIDE(COUNT(DISTINCT s.sku), t.global_sku_count) AS sku_share_pct, --SKU Share (%)
  SUM(s.units_sold) AS units_sold,
  SAFE_DIVIDE(SUM(s.units_sold), t.global_units_sold) AS sales_volume_share_pct,
  SUM(s.revenue) AS total_revenue,
  SAFE_DIVIDE(SUM(s.revenue), t.global_revenue) AS revenue_contribution_pct, --Revenue Contribution (%)
  -- Sell-Through Rate (STR) = Units Sold / Initial Stock Allocated
  SAFE_DIVIDE(SUM(s.units_sold), SUM(s.sl_ton_kho)) AS sell_through_rate_pct --Sell-Through Rate (STR %)
FROM 
  sku_performance s
CROSS JOIN 
  company_totals t
WHERE i_type = 0
GROUP BY 1,2,global_sku_count,global_units_sold,global_revenue

union all

-- =========================================================================
-- REPORT 2: PERFORMANCE BY BST
-- =========================================================================
SELECT
 IFNULL(BST,'N/A') AS group_category,
 IFNULL(bst,'N/A') AS bst,
 COUNT(DISTINCT s.sku) AS sku_count,
  SAFE_DIVIDE(COUNT(DISTINCT s.sku), t.global_sku_count) AS sku_share_pct, --SKU Share (%)
  SUM(s.units_sold) AS units_sold,
  SAFE_DIVIDE(SUM(s.units_sold), t.global_units_sold) AS sales_volume_share_pct,
  SUM(s.revenue) AS total_revenue,
  SAFE_DIVIDE(SUM(s.revenue), t.global_revenue) AS revenue_contribution_pct, --Revenue Contribution (%)
  -- Sell-Through Rate (STR) = Units Sold / Initial Stock Allocated
  SAFE_DIVIDE(SUM(s.units_sold), SUM(s.sl_ton_kho)) AS sell_through_rate_pct --Sell-Through Rate (STR %)
FROM 
  sku_performance s
CROSS JOIN 
  company_totals t
WHERE i_type = 1
GROUP BY 1,2,global_sku_count,global_units_sold,global_revenue
)

