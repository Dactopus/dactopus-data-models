{{ config(severity=env_var('DACTOPUS_STRICT_TESTS', 'warn')) }}
-- An order's lines after discounts and without tax, with its fees, make
-- its subtotal (total less shipping and tax). Line totals are not rounded
-- and amounts converted from another currency are rounded apart, so a
-- cent of difference is allowed; on the test store the difference was
-- under one (74.397 against 74.39, prices with tax).
-- A warning: CDC syncs each table apart, so a run can see an order before
-- its items, and the next run completes it. CI makes it an error
-- (DACTOPUS_STRICT_TESTS=error).
SELECT o.order_id, o.subtotal, o.fee_total, l.line_total
FROM {{ ref('orders') }} AS o
LEFT JOIN
(
    SELECT order_id, sum(line_total) AS line_total
    FROM {{ ref('order_lines') }}
    GROUP BY order_id
) AS l ON l.order_id = o.order_id
WHERE abs(o.subtotal - ifNull(l.line_total, 0) - o.fee_total) > 0.01
