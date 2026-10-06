{{ config(unique_key='order_id', order_by='(order_date, order_id, line_id)') }}
-- One row per line of an order: the lines of the order's latest version
-- (input.sql), each as last loaded: the goods sold. Lines of test orders
-- are left out, and so are gift cards sold and the tip (see orders.sql).
-- Keyed by order_id for refreshing: an order's lines are replaced together,
-- so a line missing from its order's latest version goes too.
WITH
orders AS (
    SELECT id, updated_at, processed_at, taxes_included, total_tip
    {% if is_incremental() %}
    -- Orders loaded since the last run, and orders whose lines were: the
    -- lines of a version may come in a later insert than the order.
    FROM {{ shopify_latest('orders', 'id', where="id IN " ~ shopify_loaded_since('orders') ~ " OR id IN " ~ shopify_loaded_since('order_lines', 'order_id')) }}
    {% else %}
    FROM {{ shopify_latest('orders', 'id') }}
    {% endif %}
    WHERE NOT test
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
    -- Divided in Decimal128: Decimal64 at scale 6 overflows from a line of
    -- about 9.2 million, common in currencies such as IDR or VND.
    if(o.taxes_included, toDecimal64(round(toDecimal128(l.original_total, 6) / (1 + l.tax_rate), 2), 4) - line_total, l.discount_allocated) AS discount_total,
    -- When the line was loaded; the next incremental run starts from it.
    l.loaded_at AS loaded_at
FROM {{ shopify_latest('order_lines', 'order_id, id, order_updated_at', version='order_updated_at', where='order_id IN (SELECT id FROM orders)') }} AS l
INNER JOIN orders AS o ON l.order_id = o.id AND l.order_updated_at = o.updated_at
-- The tip line has no flag of its own. No product, no tax and nothing to
-- ship alone would take a custom item too, such as a download (#1013 on
-- the development store), so its amount must also be the order's tip.
-- ponytail: a custom item of that kind costing exactly the tip goes too.
WHERE NOT l.is_gift_card
  AND NOT (l.product_id IS NULL AND NOT l.taxable AND NOT l.requires_shipping
           AND o.total_tip > 0 AND l.original_total = o.total_tip)
