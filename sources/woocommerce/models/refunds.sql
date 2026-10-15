{{ config(unique_key='order_id', order_by='(refund_date, refund_id)',
          pre_hook=["{{ woocommerce_reading() }}", "{{ woocommerce_delete_changed(in_comment=true) }}"],
          post_hook="{{ woocommerce_read() }}") }}
-- One row per refund of an order, in its current state (input.sql). A
-- refund is a row of wc_orders of type shop_order_refund, its order in
-- parent_order_id, made through the store's admin or a payment gateway
-- (wc_create_refund, https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/includes/wc-order-functions.php).
-- Keyed by order_id for refreshing: an order's refunds are replaced
-- together, so a deleted refund goes too. The next incremental run
-- starts from the sync position in the table's comment
-- (woocommerce_reading).
{% set ids = woocommerce_changed_orders(in_comment=true) if is_incremental() else none %}
WITH
orders AS (
    SELECT id FROM {{ woocommerce_orders('id IN ' ~ ids if ids else 'true') }}
),
refunds AS (
    SELECT
        id, parent_order_id, ifNull(tax_amount, 0) AS tax_amount, ifNull(total_amount, 0) AS total_amount,
        toTimeZone(assumeNotNull(date_created_gmt), 'UTC') AS refund_time, _peerdb_synced_at AS synced_at
    FROM {{ woocommerce_current('wc_orders', 'id', 'parent_order_id IN (SELECT id FROM orders)') }}
    WHERE type = 'shop_order_refund'
),
-- A refund of shipping keeps it here, negative.
operational AS (
    SELECT order_id, ifNull(shipping_total_amount, 0) AS shipping_total_amount, ifNull(shipping_tax_amount, 0) AS shipping_tax_amount
    FROM {{ woocommerce_current('wc_order_operational_data', 'id', 'order_id IN (SELECT id FROM refunds)') }}
),
-- Items refunded: the refund's line items, quantities negative. A refund
-- of an amount alone has none.
quantities AS (
    SELECT i.order_id AS refund_id, -sum(toInt64OrZero(ifNull(m.meta_value, ''))) AS quantity
    FROM {{ woocommerce_current('woocommerce_order_items', 'order_item_id', 'order_id IN (SELECT id FROM refunds)') }} AS i
    INNER JOIN {{ woocommerce_current('woocommerce_order_itemmeta', 'meta_id',
                                      "meta_key = '_qty' AND order_item_id IN (SELECT order_item_id FROM "
                                      ~ source('woocommerce_raw', 'woocommerce_order_items') ~ " WHERE order_id IN (SELECT id FROM refunds))") }} AS m
        ON m.order_item_id = i.order_item_id
    WHERE i.order_item_type = 'line_item'
    GROUP BY i.order_id
),
-- A refund's amounts are converted by its own rate, which multi-currency
-- plugins copy from the order, else by its order's (orders.sql).
rates AS (
    SELECT
        f.id AS refund_id,
        if(rf.rate_mul IS NULL, ro.rate_mul, rf.rate_mul) AS rate_mul,
        if(rf.rate_mul IS NULL, ro.rate_div, rf.rate_div) AS rate_div,
        if(rf.rate_mul IS NULL, ro.rate_fox, rf.rate_fox) AS rate_fox
    FROM refunds AS f
    LEFT JOIN {{ woocommerce_rates('(SELECT id FROM refunds)') }} AS rf ON rf.order_id = f.id
    LEFT JOIN {{ woocommerce_rates('(SELECT id FROM orders)') }} AS ro ON ro.order_id = f.parent_order_id
)
SELECT
    f.id AS refund_id,
    f.parent_order_id AS order_id,
    -- Date of the refund in the store's time zone.
    toDate(f.refund_time, '{{ var("woocommerce_timezone") }}') AS refund_date,
    f.refund_time AS refund_time,
    -- What was paid back, positive: lines, shipping, fees and an amount
    -- without lines together. The refund's total is negative; it equals
    -- the _refund_amount meta on every refund of the test store.
    -{{ woocommerce_total('f.total_amount', 'op.shipping_total_amount', 'op.shipping_tax_amount', 'f.tax_amount') }} AS refunded_amount,
    ifNull(q.quantity, 0) AS refunded_quantity,
    -- When the refund's row was synced; the next incremental run starts
    -- from the latest one while the table's comment has no position.
    f.synced_at AS synced_at
FROM refunds AS f
LEFT JOIN operational AS op ON op.order_id = f.id
LEFT JOIN quantities AS q ON q.refund_id = f.id
LEFT JOIN rates AS r ON r.refund_id = f.id
