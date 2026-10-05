{{ config(unique_key='order_id', order_by='(order_date, order_id)') }}
-- One row per order: the latest version of each order (input.sql), test
-- orders left out.
--
-- The test-order filter, the lowercased statuses and the customer's order
-- sequence (new_vs_repeat) are adapted from Fivetran's dbt_shopify,
-- models/graphql/shopify_gql__orders.sql (https://github.com/fivetran/dbt_shopify,
-- Apache License 2.0, Copyright © 2025 Fivetran Inc.). Changed here: statuses
-- are mapped to the canonical values, and the sequence follows processed_at
-- and skips guests and cancelled orders.
SELECT * FROM (
SELECT
    o.id AS order_id,
    o.name AS order_number,
    -- processedAt, the date Shopify's reports use, in the shop's time zone.
    toDate(o.processed_at, '{{ var("shopify_timezone") }}') AS order_date,
    o.processed_at AS order_time,
    o.updated_at AS updated_at,
    o.customer_id AS customer_id,
    o.email AS customer_email,
    o.currency_code AS currency,
    o.total_price AS total,
    -- Shipping after its discounts, without tax when prices include it.
    o.shipping_price - if(o.taxes_included, o.shipping_tax, toDecimal64(0, 4)) AS shipping_total,
    o.total_tax AS tax_total,
    total - shipping_total - tax_total AS subtotal,
    -- The lines' discounts without tax, their share of order-level
    -- discounts included, as Shopify's Discounts are; a shipping discount
    -- is not one of them
    -- (https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/finances-report).
    l.discount_total AS discount_total,
    o.total_refunded AS refunded_total,
    total - refunded_total AS net_total,
    o.taxes_included AS taxes_included,
    -- https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFinancialStatus
    -- A value not listed here is NULL and fails the not_null test.
    multiIf(
        o.display_financial_status IN ('AUTHORIZED', 'PENDING', 'PARTIALLY_PAID', 'EXPIRED'), 'unpaid',
        o.display_financial_status = 'PAID', 'paid',
        o.display_financial_status IN ('PARTIALLY_REFUNDED', 'REFUNDED', 'VOIDED'), lower(o.display_financial_status),
        NULL) AS financial_status,
    -- https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFulfillmentStatus
    -- OPEN and RESTOCKED are deprecated for UNFULFILLED, PENDING_FULFILLMENT
    -- for IN_PROGRESS. A download needs no shipping, yet the store shows it
    -- UNFULFILLED.
    multiIf(
        o.display_fulfillment_status IN ('UNFULFILLED', 'IN_PROGRESS', 'ON_HOLD', 'SCHEDULED', 'REQUEST_DECLINED',
                                         'OPEN', 'RESTOCKED', 'PENDING_FULFILLMENT'), 'unfulfilled',
        o.display_fulfillment_status = 'PARTIALLY_FULFILLED', 'partially_fulfilled',
        o.display_fulfillment_status IN ('FULFILLED', 'FULFILLMENT_NOT_REQUIRED'), 'fulfilled',
        NULL) AS fulfillment_status,
    o.display_financial_status AS display_financial_status,
    o.display_fulfillment_status AS display_fulfillment_status,
    o.cancelled_at IS NOT NULL AS is_cancelled,
    o.source_name AS channel,
    o.discount_codes AS discount_codes,
    length(o.discount_codes) AS discount_code_count,
    o.shipping_country_code AS shipping_country,
    o.shipping_province_code AS shipping_region,
    o.shipping_city AS shipping_city,
    o.shipping_zip AS shipping_postcode,
    l.line_item_count AS line_item_count,
    l.item_quantity AS item_quantity,
    -- The customer's orders numbered by processed_at; cancelled orders and
    -- guests have no number.
    if(o.customer_id IS NULL OR is_cancelled, NULL,
       row_number() OVER (PARTITION BY o.customer_id, is_cancelled ORDER BY o.processed_at, o.id)) AS customer_order_number,
    multiIf(customer_order_number = 1, 'new', customer_order_number > 1, 'repeat', NULL) AS new_vs_repeat
FROM {{ shopify_latest('orders', 'id') }} AS o
LEFT JOIN
(
    SELECT order_id, count() AS line_item_count, sum(quantity) AS item_quantity, toDecimal64(sum(discount_total), 4) AS discount_total
    FROM {{ ref('order_lines') }}
    GROUP BY order_id
) AS l ON l.order_id = o.id
WHERE NOT o.test
)
{% if is_incremental() %}
-- Orders changed since the last run, and every order of their customers,
-- under any version: a cancel or a back-dated order renumbers the others.
-- The sequence is numbered over all orders first, then filtered, so every
-- run reads every version of every order: cheap for orders, and a
-- deployment can collapse old versions (input.sql).
WHERE order_id IN (SELECT id FROM {{ source('shopify_raw', 'orders') }} WHERE updated_at >= {{ shopify_window_start('updated_at') }})
   OR customer_id IN (
       SELECT customer_id FROM {{ source('shopify_raw', 'orders') }}
       WHERE id IN (SELECT id FROM {{ source('shopify_raw', 'orders') }} WHERE updated_at >= {{ shopify_window_start('updated_at') }}))
{% endif %}
