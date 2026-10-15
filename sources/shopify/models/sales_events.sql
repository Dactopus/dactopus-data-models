{{ config(materialized='table', order_by='(event_date, event_id)') }}
-- One row per sales event, as Shopify's sales reports count sales over time
-- (https://shopify.dev/changelog/posts/shopifyql-returns-fields-deprecated-and-replaced-with-sales-reversals-fields):
-- an order at processedAt, each refund at the time it was made, and the
-- cancellation of an order at cancelledAt for what its refunds did not
-- take back. Shopify records a cancellation as a refund, of 0 money when
-- nothing was paid, which reverses the rest of the order; on the
-- development store these events match `FROM sales SHOW total_sales GROUP
-- BY order_name, day` for every order and day. Not yet seen: a
-- cancellation and a refund on different days, which this may split
-- differently from the store; and an order edit, which the store dates on
-- the day of the edit and this on the day of the order (#16).
-- Rebuilt from orders and refunds on every run: two narrow reads, and the
-- events cannot drift from the orders they come from.
SELECT
    concat('order-', toString(order_id)) AS event_id,
    'order' AS event_type,
    order_id,
    order_date AS event_date,
    order_time AS event_time,
    total AS amount
FROM {{ ref('orders') }}
UNION ALL
SELECT
    concat('refund-', toString(refund_id)) AS event_id,
    'refund' AS event_type,
    order_id,
    refund_date AS event_date,
    refund_time AS event_time,
    -refunded_amount AS amount
FROM {{ ref('refunds') }}
UNION ALL
SELECT
    concat('cancellation-', toString(order_id)) AS event_id,
    'cancellation' AS event_type,
    order_id,
    -- Set on every cancelled order; the sorting key may not be Nullable.
    toDate(assumeNotNull(cancelled_time), '{{ var("shopify_timezone") }}') AS event_date,
    assumeNotNull(cancelled_time) AS event_time,
    -(total - refunded_total) AS amount
FROM {{ ref('orders') }}
WHERE is_cancelled AND total != refunded_total
{{ shopify_query_settings() }}
