CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_product_inventory_overseas_shipment(number_year_back INT64)
AS
SELECT 
      oi.order_id,
      order_date,
      CASE 
          WHEN status_name = 'shipped' AND o.warehouse_id IN ('878504e9-fb75-4870-8504-b2ecdbc097ba') --Kho Thái (Back-up)
          THEN DATE_ADD(DATE(order_date), INTERVAL 10 DAY)
          WHEN status_name = 'shipped' AND o.warehouse_id IN ('76be7836-6dc5-4b1c-9e48-b18e43127453') --Kho Trung Quốc (Back-up)
          THEN DATE_ADD(DATE(order_date), INTERVAL 14 DAY)
      ELSE NULL
      END AS expected_delivery_date,
      status,
      status_name,
      oi.product_id,
      p.product_code,
      oi.product_name,
      v.variation_display_id AS variation_code,
      v.variation_attributes,
      oi.retail_price AS retail_price_vn,
      
      oi.cart_quantity AS total_inventory_qty,
      CASE
        WHEN status_name = 'shipped' THEN oi.cart_quantity
        ELSE 0
      END  inventory_qty_shipped,
      CASE
        WHEN status_name = 'submitted' THEN oi.cart_quantity
        ELSE 0
      END  inventory_qty_not_shipped,
      CASE
        WHEN status_name = 'part_returned' THEN oi.cart_quantity
        ELSE 0
      END inventory_qty_returned_to_origin,
      oi.warehouse_id,
      o.warehouse_name
    FROM `marine-cycle-484213-b4.core_pancake.core_order` AS o 
    JOIN  `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.variation_id = v.variation_id
    WHERE 1=1
    AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
    --AND DATE(o.inserted_at) >= '2026-03-31' 
    AND status_name NOT IN ('canceled')
    AND o.warehouse_id IN ('878504e9-fb75-4870-8504-b2ecdbc097ba','76be7836-6dc5-4b1c-9e48-b18e43127453')
    ORDER BY 2 DESC;
