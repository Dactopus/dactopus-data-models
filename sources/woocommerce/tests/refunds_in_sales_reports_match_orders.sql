{{ config(severity=env_var('DACTOPUS_STRICT_TESTS', 'warn')) }}
-- A refund carries the flag of its order (orders.in_sales_reports): none
-- differs. refunds.sql computes the flag from the order's own tables
-- (woocommerce_in_sales_reports), as orders.sql does, so a difference is
-- a formula that drifted apart.
-- A warning: CDC syncs each table apart, so a run can see an order's status
-- or payment date before the refunds rows are rebuilt, and the next
-- run completes them. CI makes it an error (DACTOPUS_STRICT_TESTS=error).
SELECT l.refund_id, l.order_id, l.in_sales_reports, o.in_sales_reports AS order_in_sales_reports
FROM {{ ref('refunds') }} AS l
INNER JOIN {{ ref('orders') }} AS o ON o.order_id = l.order_id
WHERE l.in_sales_reports != o.in_sales_reports
