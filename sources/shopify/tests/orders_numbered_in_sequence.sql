-- Each customer's orders are numbered 1 to n without a gap or a repeat
-- (orders.customer_order_number), so customers.number_of_orders is the
-- number of the last. An incremental run renumbers a customer's orders
-- whole; one that left some out would show here.
SELECT customer_id, count() AS numbered, max(customer_order_number) AS last, uniqExact(customer_order_number) AS distinct_numbers
FROM {{ ref('orders') }}
WHERE customer_order_number IS NOT NULL
GROUP BY customer_id
HAVING last != numbered OR distinct_numbers != numbered OR min(customer_order_number) != 1
