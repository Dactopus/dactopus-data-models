{{ config(unique_key='order_id', order_by='(order_date, order_id, line_id)') }}
-- One row per line of an order: the lines of the order's latest version
-- (input.sql), each as last loaded. Lines of test orders are left out.
-- Keyed by order_id for refreshing: an order's lines are replaced together,
-- so a line missing from its order's latest version goes too.
WITH
orders AS (
    SELECT id, updated_at, processed_at, taxes_included
    FROM {{ shopify_latest('orders', 'id') }}
    WHERE NOT test
    {% if is_incremental() %}
    AND id IN (SELECT id FROM {{ source('shopify_raw', 'orders') }} WHERE updated_at >= {{ shopify_window_start('order_updated_at') }})
    {% endif %}
)
SELECT
    l.id AS line_id,
    l.order_id AS order_id,
    o.updated_at AS order_updated_at,
    toDate(o.processed_at, '{{ var("shopify_timezone") }}') AS order_date,
    l.product_id AS product_id,
    l.variant_id AS variant_id,
    l.sku AS sku,
    l.title AS title,
    l.variant_title AS variant_title,
    l.quantity AS quantity,
    l.current_quantity AS current_quantity,
    -- After every discount and without tax, whether or not the shop's prices
    -- include tax. With taxes included, original_total and the discounts
    -- have tax inside, and taking the line's tax off leaves the order's
    -- total less shipping and tax (seen on a development store: 1399.90 -
    -- 10 - 161.05 = 1228.85).
    l.original_total - l.discount_allocated - if(o.taxes_included, l.total_tax, toDecimal64(0, 4)) AS line_total,
    l.total_tax AS line_tax,
    -- The line's discounts without tax: its price without tax before
    -- discounts less after. With taxes included, discountAllocations have
    -- tax inside; the tax is not taken from them in proportion, as Shopify
    -- may compute the line's tax on the price before discounts (seen on a
    -- development store: 1399.90 at 13% with 10 off, tax 161.05).
    -- ponytail: a line's rates are added up; compound taxes would need
    -- their order.
    if(o.taxes_included, toDecimal64(round(toDecimal64(l.original_total, 6) / (1 + l.tax_rate), 2), 4) - line_total, l.discount_allocated) AS discount_total
FROM
(
    SELECT * FROM {{ source('shopify_raw', 'order_lines') }}
    WHERE order_id IN (SELECT id FROM orders)
    ORDER BY loaded_at DESC
    LIMIT 1 BY order_id, id, order_updated_at
) AS l
INNER JOIN orders AS o ON l.order_id = o.id AND l.order_updated_at = o.updated_at
