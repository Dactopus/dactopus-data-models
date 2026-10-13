-- The sales events of an order the store's reports count add up to its
-- net_total, whichever statuses the reports exclude: net_revenue by the
-- month of the order then equals the orders' net_total. Both come from
-- orders and refunds of the same run, so they never differ by timing.
SELECT o.order_id, o.net_total, e.amount
FROM {{ ref('orders') }} AS o
LEFT JOIN
(
    SELECT order_id, sum(amount) AS amount
    FROM {{ ref('sales_events') }}
    GROUP BY order_id
) AS e ON e.order_id = o.order_id
WHERE o.in_sales_reports AND o.net_total != ifNull(e.amount, 0)
