CREATE VIEW `marine-cycle-484213-b4.dev_staging.stg_pancake__order`
OPTIONS(
  description="The current daily Pancake extraction batch, typed to the supplied core-table contract. It contains up to 30 business days of order-item rows; order headers repeat at item grain."
)
AS select
    raw._PARTITIONTIME as proc_date,
    nullif(trim(raw._item_id_), '') as order_item_id,
    nullif(trim(raw.product_id), '') as product_id,
    nullif(trim(raw.variation_id), '') as variation_id,
    
    case
        when nullif(trim(raw.quantity_ordered), '') in ('True', 'true') then 1
        when nullif(trim(raw.quantity_ordered), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.quantity_ordered), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.quantity_ordered), '') as numeric) as int64)
    end as quantity_ordered,
    
    case
        when nullif(trim(raw.quantity_returned), '') in ('True', 'true') then 1
        when nullif(trim(raw.quantity_returned), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.quantity_returned), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.quantity_returned), '') as numeric) as int64)
    end as quantity_returned,
    
    case
        when nullif(trim(raw.quantity_returning), '') in ('True', 'true') then 1
        when nullif(trim(raw.quantity_returning), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.quantity_returning), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.quantity_returning), '') as numeric) as int64)
    end as quantity_returning,
    
    case
        when nullif(trim(raw.return_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.return_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.return_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.return_count), '') as numeric) as int64)
    end as return_count,
    
    case
        when nullif(trim(raw.is_wholesale), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_wholesale), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_wholesale), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_wholesale), '') as numeric) as int64)
    end as is_wholesale,
    
    case
        when nullif(trim(raw.is_discount_percent), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_discount_percent), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_discount_percent), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_discount_percent), '') as numeric) as int64)
    end as is_discount_percent,
    
    case
        when nullif(trim(raw.is_one_time_product), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_one_time_product), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_one_time_product), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_one_time_product), '') as numeric) as int64)
    end as is_one_time_product,
    
    case
        when nullif(trim(raw.cart_quantity), '') in ('True', 'true') then 1
        when nullif(trim(raw.cart_quantity), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.cart_quantity), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.cart_quantity), '') as numeric) as int64)
    end as cart_quantity,
    
    case
        when nullif(trim(raw.exchange_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.exchange_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.exchange_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.exchange_count), '') as numeric) as int64)
    end as exchange_count,
    safe_cast(nullif(trim(raw.unit_discount), '') as float64) as unit_discount,
    
    case
        when nullif(trim(raw.item_total_discount), '') in ('True', 'true') then 1
        when nullif(trim(raw.item_total_discount), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.item_total_discount), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.item_total_discount), '') as numeric) as int64)
    end as item_total_discount,
    nullif(trim(raw.product_name), '') as product_name,
    safe_cast(nullif(trim(raw.exact_price), '') as float64) as exact_price,
    safe_cast(nullif(trim(raw.retail_price), '') as float64) as retail_price,
    safe_cast(nullif(trim(raw.original_retail_price), '') as float64) as original_retail_price,
    safe_cast(nullif(trim(raw.average_price), '') as float64) as average_price,
    safe_cast(nullif(trim(raw.last_import_price), '') as float64) as last_import_price,
    nullif(trim(raw.product_detail), '') as product_detail,
    nullif(trim(raw.product_fields), '') as product_fields,
    nullif(trim(raw.order_id), '') as order_id,
    
    case
        when nullif(trim(raw.system_id), '') in ('True', 'true') then 1
        when nullif(trim(raw.system_id), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.system_id), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.system_id), '') as numeric) as int64)
    end as system_id,
    nullif(trim(raw.status), '') as status,
    nullif(trim(raw.status_name), '') as status_name,
    coalesce(
        safe.parse_datetime('%Y%m%d%H%M%S', nullif(trim(raw.inserted_at), '')),
        datetime(safe_cast(nullif(trim(raw.inserted_at), '') as timestamp), 'Asia/Ho_Chi_Minh')
    ) as inserted_at,
    nullif(trim(raw.updated_at), '') as updated_at,
    
    case
        when nullif(trim(raw.is_received_at_shop), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_received_at_shop), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_received_at_shop), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_received_at_shop), '') as numeric) as int64)
    end as is_received_at_shop,
    nullif(trim(raw.order_currency), '') as order_currency,
    safe_cast(nullif(trim(raw.total_price), '') as float64) as total_price,
    safe_cast(nullif(trim(raw.total_price_after_sub_discount), '') as float64) as total_price_after_sub_discount,
    safe_cast(nullif(trim(raw.total_discount), '') as float64) as total_discount,
    
    case
        when nullif(trim(raw.total_quantity), '') in ('True', 'true') then 1
        when nullif(trim(raw.total_quantity), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.total_quantity), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.total_quantity), '') as numeric) as int64)
    end as total_quantity,
    safe_cast(nullif(trim(raw.shipping_fee), '') as float64) as shipping_fee,
    safe_cast(nullif(trim(raw.marketplace_fee), '') as float64) as marketplace_fee,
    safe_cast(nullif(trim(raw.partner_fee), '') as float64) as partner_fee,
    safe_cast(nullif(trim(raw.surcharge_amount), '') as float64) as surcharge_amount,
    safe_cast(nullif(trim(raw.buyer_total_amount), '') as float64) as buyer_total_amount,
    safe_cast(nullif(trim(raw.cod_money_to_collect), '') as float64) as cod_money_to_collect,
    safe_cast(nullif(trim(raw.cod), '') as float64) as cod,
    safe_cast(nullif(trim(raw.tax_amount), '') as float64) as tax_amount,
    safe_cast(nullif(trim(raw.paid_cash), '') as float64) as paid_cash,
    safe_cast(nullif(trim(raw.prepaid_amount), '') as float64) as prepaid_amount,
    safe_cast(nullif(trim(raw.transfer_amount), '') as float64) as transfer_amount,
    safe_cast(nullif(trim(raw.charged_by_card), '') as float64) as charged_by_card,
    safe_cast(nullif(trim(raw.charged_by_momo), '') as float64) as charged_by_momo,
    safe_cast(nullif(trim(raw.charged_by_qrpay), '') as float64) as charged_by_qrpay,
    safe_cast(nullif(trim(raw.bank_payments), '') as float64) as bank_payments,
    safe_cast(nullif(trim(raw.exchange_payment_info), '') as float64) as exchange_payment_info,
    
    case
        when nullif(trim(raw.is_customer_paid_fee), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_customer_paid_fee), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_customer_paid_fee), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_customer_paid_fee), '') as numeric) as int64)
    end as is_customer_paid_fee,
    nullif(trim(raw.shipping_address_commune_name), '') as shipping_address_commune_name,
    nullif(trim(raw.shipping_address_province_name), '') as shipping_address_province_name,
    nullif(trim(raw.warehouse_id), '') as warehouse_id,
    nullif(trim(raw.warehouse_info_name), '') as warehouse_name,
    
    case
        when nullif(trim(raw.marketplace_id), '') in ('True', 'true') then 1
        when nullif(trim(raw.marketplace_id), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.marketplace_id), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.marketplace_id), '') as numeric) as int64)
    end as marketplace_id,
    
    case
        when nullif(trim(raw.order_sources), '') in ('True', 'true') then 1
        when nullif(trim(raw.order_sources), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.order_sources), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.order_sources), '') as numeric) as int64)
    end as order_sources,
    nullif(trim(raw.order_sources_name), '') as order_sources_name,
    nullif(trim(raw.notes), '') as notes,
    nullif(trim(raw.print_notes), '') as print_notes,
    nullif(trim(raw.tags), '') as tags,
    nullif(trim(raw.customer_currency), '') as customer_currency,
    nullif(trim(raw.customer_customer_id), '') as customer_customer_id,
    
    case
        when nullif(trim(raw.customer_succeed_order_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.customer_succeed_order_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.customer_succeed_order_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.customer_succeed_order_count), '') as numeric) as int64)
    end as customer_succeed_order_count,
    nullif(trim(raw.customer_inserted_at), '') as customer_inserted_at,
    safe_cast(nullif(trim(raw.customer_is_block), '') as float64) as is_block_customer,
    nullif(trim(raw.customer_updated_at), '') as customer_updated_at,
    
    case
        when nullif(trim(raw.customer_order_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.customer_order_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.customer_order_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.customer_order_count), '') as numeric) as int64)
    end as customer_order_count,
    
    case
        when nullif(trim(raw.customer_returned_order_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.customer_returned_order_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.customer_returned_order_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.customer_returned_order_count), '') as numeric) as int64)
    end as customer_returned_order_count,
    safe_cast(nullif(trim(raw.customer_purchased_amount), '') as float64) as customer_purchased_amount,
    nullif(trim(raw.customer_last_order_at), '') as customer_last_order_at,
    nullif(trim(raw.customer_gender), '') as customer_gender,
    nullif(trim(raw.assigning_seller_name), '') as assigning_seller_name,
    nullif(trim(raw.assigning_seller_email), '') as assigning_seller_email,
    nullif(trim(raw.assigning_care_name), '') as assigning_care_name,
    nullif(trim(raw.assigning_care_email), '') as assigning_care_email,
    nullif(trim(raw.time_assigned_seller), '') as time_assigned_seller,
    nullif(trim(raw.time_assigned_care), '') as time_assigned_care,
    nullif(trim(raw.time_sent_partner), '') as time_sent_partner,
    
    case
        when nullif(trim(raw.is_exchange_order), '') in ('True', 'true') then 1
        when nullif(trim(raw.is_exchange_order), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.is_exchange_order), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.is_exchange_order), '') as numeric) as int64)
    end as is_exchange_order,
    safe_cast(nullif(trim(raw.exchange_value), '') as float64) as exchange_value,
    
    case
        when nullif(trim(raw.return_reason_code), '') in ('True', 'true') then 1
        when nullif(trim(raw.return_reason_code), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.return_reason_code), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.return_reason_code), '') as numeric) as int64)
    end as return_reason_code,
    nullif(trim(raw.return_reason), '') as return_reason,
    nullif(trim(raw.last_editor_name), '') as last_editor_name,
    nullif(trim(raw.last_editor_email), '') as last_editor_email,
    nullif(trim(raw.creator_name), '') as creator_name,
    nullif(trim(raw.creator_email), '') as creator_email,
    nullif(trim(raw.partner), '') as partner,
    
    case
        when nullif(trim(raw.items_count), '') in ('True', 'true') then 1
        when nullif(trim(raw.items_count), '') in ('False', 'false') then 0
        when regexp_contains(nullif(trim(raw.items_count), ''), r'^[+-]?[0-9]+(\.0+)?$')
            then safe_cast(safe_cast(nullif(trim(raw.items_count), '') as numeric) as int64)
    end as items_count,
    nullif(trim(raw.advanced_platform_fee_affiliate_commission), '') as advanced_platform_fee_affiliate_commission,
    safe_cast(nullif(trim(raw.advanced_platform_fee_diff_shipping_fee), '') as float64) as advanced_platform_fee_diff_shipping_fee,
    safe_cast(nullif(trim(raw.advanced_platform_fee_marketplace_voucher), '') as float64) as advanced_platform_fee_marketplace_voucher,
    safe_cast(nullif(trim(raw.advanced_platform_fee_payment_fee), '') as float64) as advanced_platform_fee_payment_fee,
    safe_cast(nullif(trim(raw.advanced_platform_fee_seller_transaction_fee), '') as float64) as advanced_platform_fee_seller_transaction_fee,
    safe_cast(nullif(trim(raw.advanced_platform_fee_service_fee), '') as float64) as advanced_platform_fee_service_fee,
    coalesce(
        safe.parse_datetime('%Y%m%d%H%M%S', nullif(trim(raw.updated_at), '')),
        datetime(safe_cast(nullif(trim(raw.updated_at), '') as timestamp), 'Asia/Ho_Chi_Minh')
    ) as updated_at_datetime,
    to_hex(md5(to_json_string(struct(
        raw._PARTITIONTIME as proc_date,
        raw.order_id,
        raw.system_id,
        raw.status,
        raw.status_name,
        raw.inserted_at,
        raw.updated_at,
        raw.is_received_at_shop,
        raw.order_currency,
        raw.total_price,
        raw.total_price_after_sub_discount,
        raw.total_discount,
        raw.total_quantity,
        raw.shipping_fee,
        raw.marketplace_fee,
        raw.partner_fee,
        raw.surcharge_amount,
        raw.buyer_total_amount,
        raw.cod_money_to_collect,
        raw.cod,
        raw.tax_amount,
        raw.paid_cash,
        raw.prepaid_amount,
        raw.transfer_amount,
        raw.charged_by_card,
        raw.charged_by_momo,
        raw.charged_by_qrpay,
        raw.bank_payments,
        raw.exchange_payment_info,
        raw.is_customer_paid_fee,
        raw.shipping_address_commune_name,
        raw.shipping_address_province_name,
        raw.warehouse_id,
        raw.warehouse_info_name,
        raw.marketplace_id,
        raw.order_sources,
        raw.order_sources_name,
        raw.notes,
        raw.print_notes,
        raw.tags,
        raw.customer_currency,
        raw.customer_customer_id,
        raw.customer_succeed_order_count,
        raw.customer_inserted_at,
        raw.customer_is_block,
        raw.customer_updated_at,
        raw.customer_order_count,
        raw.customer_returned_order_count,
        raw.customer_purchased_amount,
        raw.customer_last_order_at,
        raw.customer_gender,
        raw.assigning_seller_name,
        raw.assigning_seller_email,
        raw.assigning_care_name,
        raw.assigning_care_email,
        raw.time_assigned_seller,
        raw.time_assigned_care,
        raw.time_sent_partner,
        raw.is_exchange_order,
        raw.exchange_value,
        raw.return_reason_code,
        raw.return_reason,
        raw.last_editor_name,
        raw.last_editor_email,
        raw.creator_name,
        raw.creator_email,
        raw.partner,
        raw.items_count,
        raw.advanced_platform_fee_affiliate_commission,
        raw.advanced_platform_fee_diff_shipping_fee,
        raw.advanced_platform_fee_marketplace_voucher,
        raw.advanced_platform_fee_payment_fee,
        raw.advanced_platform_fee_seller_transaction_fee,
        raw.advanced_platform_fee_service_fee
    )))) as order_version_key
from `marine-cycle-484213-b4`.`raw_pancake`.`raw_order` as raw
where raw._PARTITIONTIME >= timestamp(current_date('Asia/Ho_Chi_Minh'), 'Asia/Ho_Chi_Minh')
    and raw._PARTITIONTIME < timestamp(date_add(current_date('Asia/Ho_Chi_Minh'), interval 1 day), 'Asia/Ho_Chi_Minh');
