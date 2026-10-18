--truncate table `marine-cycle-484213-b4.surfosm.core_surfosm_order`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_order`
PARTITION BY DATE(inserted_at)
CLUSTER BY  parameter_date,order_number,channel,status
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  channel,
  shipping,
  status,
  status_code,
  customer_name,
  customer_address,
  customer_district,
  customer_province,
  customer_postal_code,
  customer_phone_no,
  customer_email,
  payment_paid_at,
  payment_shipping_fee_original,
  payment_shipping_fee_discount_platform,
  payment_shipping_fee_discount_seller,
  payment_shipping_fee,
  payment_discount_platform_voucher,
  payment_discount_platform_payment_promotion,
  payment_discount_platform_order,
  payment_discount_platform_total,
  payment_coupon_seller,
  payment_discount_seller,
  payment_discount_seller_total,
  payment_subtotal,
  payment_discount,
  payment_total
FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
WHERE DATE(proc_date) = "2026-08-21"