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
    -- What the order sold: the total less tips and gift cards sold, which
    -- Shopify's sales reports leave out. Import duties and fees stay in it,
    -- as in Shopify's total sales (input.sql). A gift card counts when it is
    -- spent, as part of the order it pays for
    -- (https://shopify.dev/docs/api/shopifyql/latest/schemas/sales_revenue/sales:
    -- gift_card_gross_sales apart from gross_sales; on the development
    -- store #1016, 40 of goods, a 50 gift card and 10 shipping, has total
    -- sales 50). Tips have a report of their own
    -- (https://help.shopify.com/en/manual/checkout-settings/tips).
    o.total_price - o.total_tip - g.gift_card_total AS total,
    o.total_tip AS tip_total,
    g.gift_card_total AS gift_card_total,
    -- Shipping after its discounts, without tax when prices include it.
    o.shipping_price - if(o.taxes_included, o.shipping_tax, toDecimal64(0, 4)) AS shipping_total,
    -- Tax on the lines, shipping and duties.
    o.total_tax AS tax_total,
    o.total_duties AS duties_total,
    o.total_additional_fees AS additional_fees_total,
    total - shipping_total - tax_total - duties_total - additional_fees_total AS subtotal,
    -- The lines' discounts without tax, their share of order-level
    -- discounts included, as Shopify's Discounts are; a shipping discount
    -- is not one of them
    -- (https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/finances-report).
    l.discount_total AS discount_total,
    -- What was paid back (totalRefundedSet) less gift cards sold and
    -- refunded, which Shopify's sales reports take off gift card sales, not
    -- as returns (on the development store #1016, its 50 gift card
    -- refunded: returns 0, total sales still 50). A refunded tip has no
    -- refund line and cannot be told apart, so it stays here (#6).
    o.total_refunded - gift_card_refunded_total AS refunded_total,
    gr.gift_card_refunded_total AS gift_card_refunded_total,
    -- What the order earned after refunds. A cancelled order earned
    -- nothing: cancelled unpaid, nothing was paid or refunded, yet total
    -- less refunded would count it whole.
    if(o.cancelled_at IS NOT NULL, toDecimal64(0, 4), total - refunded_total) AS net_total,
    o.taxes_included AS taxes_included,
    -- https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFinancialStatus
    -- unpaid: money is still expected. voided: none will come, the
    -- authorization was voided or EXPIRED ("Payment wasn't captured before
    -- the payment provider's deadline on an authorized order").
    -- A value not listed here is NULL and fails the not_null test.
    multiIf(
        o.display_financial_status IN ('AUTHORIZED', 'PENDING', 'PARTIALLY_PAID'), 'unpaid',
        o.display_financial_status = 'PAID', 'paid',
        o.display_financial_status IN ('PARTIALLY_REFUNDED', 'REFUNDED'), lower(o.display_financial_status),
        o.display_financial_status IN ('VOIDED', 'EXPIRED'), 'voided',
        NULL) AS financial_status,
    -- https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFulfillmentStatus
    -- OPEN and RESTOCKED are deprecated for UNFULFILLED, PENDING_FULFILLMENT
    -- for IN_PROGRESS. A download needs no shipping, yet the store shows it
    -- UNFULFILLED. FULFILLMENT_NOT_REQUIRED, from API 2026-10 on, is an
    -- order cancelled or refunded whole before anything was fulfilled; earlier
    -- versions return UNFULFILLED for it, and so does the package, so its
    -- numbers do not depend on the loader's API version
    -- (https://shopify.dev/changelog/posts/orderdisplayfulfillmentstatus-now-returns-fulfillmentnotrequired).
    multiIf(
        o.display_fulfillment_status IN ('UNFULFILLED', 'IN_PROGRESS', 'ON_HOLD', 'SCHEDULED', 'REQUEST_DECLINED',
                                         'FULFILLMENT_NOT_REQUIRED', 'OPEN', 'RESTOCKED', 'PENDING_FULFILLMENT'), 'unfulfilled',
        o.display_fulfillment_status = 'PARTIALLY_FULFILLED', 'partially_fulfilled',
        o.display_fulfillment_status = 'FULFILLED', 'fulfilled',
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
    multiIf(customer_order_number = 1, 'new', customer_order_number > 1, 'repeat', NULL) AS new_vs_repeat,
    -- When the version was loaded; the next incremental run starts from it.
    o.loaded_at AS loaded_at
FROM {{ shopify_latest('orders', 'id') }} AS o
LEFT JOIN
(
    -- Gift cards sold in the order's version; order_lines leaves them out.
    SELECT order_id, order_updated_at, toDecimal64(sum(original_total - discount_allocated), 4) AS gift_card_total
    FROM {{ shopify_latest('order_lines', 'order_id, id, order_updated_at', version='order_updated_at', where='is_gift_card') }}
    GROUP BY order_id, order_updated_at
) AS g ON g.order_id = o.id AND g.order_updated_at = o.updated_at
LEFT JOIN
(
    -- Refund lines of gift cards sold, each refund in its latest version.
    SELECT r.order_id AS order_id, toDecimal64(sum(rl.subtotal + rl.total_tax), 4) AS gift_card_refunded_total
    FROM {{ shopify_latest('refunds', 'id') }} AS r
    INNER JOIN {{ shopify_latest('refund_lines', 'refund_id, id, refund_updated_at', version='refund_updated_at') }} AS rl
        ON rl.refund_id = r.id AND rl.refund_updated_at = r.updated_at
    WHERE rl.line_item_id IN (SELECT id FROM {{ source('shopify_raw', 'order_lines') }} WHERE is_gift_card)
    GROUP BY r.order_id
) AS gr ON gr.order_id = o.id
LEFT JOIN
(
    SELECT order_id, count() AS line_item_count, sum(quantity) AS item_quantity, toDecimal64(sum(discount_total), 4) AS discount_total
    FROM {{ ref('order_lines') }}
    GROUP BY order_id
) AS l ON l.order_id = o.id
WHERE NOT o.test
)
{% if is_incremental() %}
-- Orders loaded since the last run, orders whose lines were (their counts
-- and discounts come from the lines) or whose refunds or refund lines were
-- (gift cards refunded), and every order of their customers,
-- under any version: a cancel or a back-dated order renumbers the others.
-- An order moved to another customer (orderCustomerSet changes updated_at,
-- seen on the development store) renumbers both: the previous customer
-- comes from this table, as an input that collapses old versions
-- (input.sql) may have lost it.
-- The sequence is numbered over all orders first, then filtered, so every
-- run reads every version of every order: cheap for orders.
{% set orders_loaded = shopify_loaded_since('orders') %}
{% set lines_loaded = shopify_loaded_since('order_lines', 'order_id') %}
WHERE order_id IN {{ orders_loaded }}
   OR order_id IN {{ lines_loaded }}
   OR order_id IN (
       SELECT order_id FROM {{ source('shopify_raw', 'refunds') }}
       WHERE id IN {{ shopify_loaded_since('refunds') }} OR id IN {{ shopify_loaded_since('refund_lines', 'refund_id') }})
   OR customer_id IN (
       SELECT customer_id FROM {{ source('shopify_raw', 'orders') }}
       WHERE id IN {{ orders_loaded }} OR id IN {{ lines_loaded }})
   OR customer_id IN (
       SELECT customer_id FROM {{ this }}
       WHERE order_id IN {{ orders_loaded }} OR order_id IN {{ lines_loaded }})
{% endif %}
