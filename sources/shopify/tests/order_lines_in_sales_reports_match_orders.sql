-- A line carries the flag of its order (orders.in_sales_reports): none
-- differs. Shopify's reports count every order, so both are true.
SELECT l.line_id, l.order_id, l.in_sales_reports, o.in_sales_reports AS order_in_sales_reports
FROM {{ ref('order_lines') }} AS l
INNER JOIN {{ ref('orders') }} AS o ON o.order_id = l.order_id
WHERE l.in_sales_reports != o.in_sales_reports
