{{ config(unique_key='order_id', order_by='(order_id, line_id)',
          pre_hook="{{ woocommerce_delete_changed(products=true) }}") }}
-- One row per line of an order: its items of type line_item, the goods
-- sold, in their current state (input.sql). Shipping, fees, coupons and tax
-- are items of other types. Keyed by order_id for refreshing: an order's
-- lines are replaced together, so a line removed from the order goes too.
{% set ids = woocommerce_changed_orders(products=true) if is_incremental() else none %}
WITH
orders AS (
    SELECT id, synced_at FROM {{ woocommerce_orders('id IN ' ~ ids if ids else 'true') }}
),
-- The orders' refunds, for what each refunded of a line.
refunds AS (
    SELECT id FROM {{ woocommerce_current('wc_orders', 'id', 'parent_order_id IN (SELECT id FROM orders)') }}
    WHERE type = 'shop_order_refund'
),
items AS (
    SELECT order_item_id, ifNull(order_item_name, '') AS order_item_name, order_id
    FROM {{ woocommerce_current('woocommerce_order_items', 'order_item_id',
                                'order_id IN (SELECT id FROM orders) OR order_id IN (SELECT id FROM refunds)') }}
    WHERE order_item_type = 'line_item'
),
-- An item's meta as columns. A refund's item has negative quantity and
-- amounts and points at the order's item it refunds (_refunded_item_id).
item_meta AS (
    SELECT
        order_item_id,
        toUInt64OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_product_id'), '')) AS product_id,
        toUInt64OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_variation_id'), '')) AS variation_id,
        toInt64OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_qty'), '')) AS qty,
        toDecimal128OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_line_subtotal'), ''), 8) AS line_subtotal,
        toDecimal128OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_line_total'), ''), 8) AS line_total,
        toDecimal128OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_line_tax'), ''), 8) AS line_tax,
        toUInt64OrZero(ifNull(argMaxIf(meta_value, meta_id, meta_key = '_refunded_item_id'), '')) AS refunded_item_id
    FROM (
        SELECT meta_id, order_item_id, meta_key, ifNull(meta_value, '') AS meta_value
        FROM {{ woocommerce_current('woocommerce_order_itemmeta', 'meta_id',
                                    'order_item_id IN (SELECT order_item_id FROM items)') }}
    )
    GROUP BY order_item_id
),
refunded AS (
    SELECT m.refunded_item_id AS order_item_id, sum(m.qty) AS qty
    FROM items AS i
    INNER JOIN item_meta AS m ON m.order_item_id = i.order_item_id
    WHERE i.order_id IN (SELECT id FROM refunds)
    GROUP BY m.refunded_item_id
),
products AS (
    SELECT toUInt64(product_id) AS product_id, ifNull(sku, '') AS sku
    FROM {{ woocommerce_current('wc_product_meta_lookup', 'product_id',
                                'toUInt64(product_id) IN (SELECT product_id FROM item_meta UNION ALL SELECT variation_id FROM item_meta)') }}
)
SELECT
    i.order_item_id AS line_id,
    i.order_id AS order_id,
    nullIf(m.product_id, 0) AS product_id,
    nullIf(m.variation_id, 0) AS variant_id,
    -- The line keeps no SKU: its product's current one, the variation's
    -- for a variation (its parent's when it has none of its own, as
    -- WooCommerce shows it). A deleted product has none.
    if(m.variation_id != 0,
       if(v.product_id != 0, coalesce(nullIf(v.sku, ''), nullIf(p.sku, '')), NULL),
       nullIf(p.sku, '')) AS sku,
    -- The product's name as it was on the order.
    i.order_item_name AS title,
    m.qty AS quantity,
    -- Less what the order's refunds took back (their quantities are
    -- negative). Cancelling an order leaves its quantities as they are.
    m.qty + ifNull(rf.qty, 0) AS current_quantity,
    -- After discounts and without tax, also when prices include tax; not
    -- rounded (16.532721 on the test store). Amounts in the store's
    -- currency (orders.sql), unrounded too.
    {{ woocommerce_convert('m.line_total', 'r', 8) }} AS line_total,
    {{ woocommerce_convert('m.line_tax', 'r', 8) }} AS line_tax,
    -- Coupons' share of the line, without tax.
    {{ woocommerce_convert('m.line_subtotal - m.line_total', 'r', 8) }} AS discount_total,
    -- When the order's row was synced; the next incremental run starts
    -- from it.
    o.synced_at AS synced_at
FROM items AS i
INNER JOIN orders AS o ON o.id = i.order_id
LEFT JOIN item_meta AS m ON m.order_item_id = i.order_item_id
LEFT JOIN refunded AS rf ON rf.order_item_id = i.order_item_id
LEFT JOIN products AS p ON p.product_id = m.product_id
LEFT JOIN products AS v ON v.product_id = m.variation_id
LEFT JOIN {{ woocommerce_rates('(SELECT id FROM orders)') }} AS r ON r.order_id = i.order_id
