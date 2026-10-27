{{ config(severity=env_var('DACTOPUS_STRICT_TESTS', 'warn')) }}
-- The sales events of an order add up to its net_total: an order less its
-- refunds, and 0 for a cancelled one, whose cancellation takes back the
-- rest. sales_events.net_revenue by the month of the order then equals
-- the orders' net_total. A warning: net_total takes refunds from the order
-- and the events from the refunds table, so a run between the loads of
-- the two can see them differ, and the next run completes them. CI keeps
-- it a warning: its staged loads deliver 1004's refund three runs before
-- the order's version that carries it, and the test warns on 1004 until
-- then. The WooCommerce package's CI makes its own check an error
-- (DACTOPUS_STRICT_TESTS=error): there the two come from one window.
SELECT o.order_id, o.net_total, e.amount
FROM {{ ref('orders') }} AS o
LEFT JOIN
(
    SELECT order_id, sum(amount) AS amount
    FROM {{ ref('sales_events') }}
    GROUP BY order_id
) AS e ON e.order_id = o.order_id
WHERE o.in_sales_reports AND o.net_total != ifNull(e.amount, 0)
