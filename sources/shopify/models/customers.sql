{{ config(materialized='table', order_by='customer_id') }}
-- One row per customer with an order Shopify's report of new and returning
-- customers counts: the orders numbered in orders.customer_order_number,
-- cancelled ones included. A customer record without such an order, a
-- newsletter subscriber or a customer of test orders only, has no row.
-- Dates are those of the numbered orders, by processed_at in the shop's
-- time zone. net_total is what the customer's orders earned after refunds
-- and cancellations, as Shopify's sales report by customer counts it
-- (total_sales), not the customer's amountSpent, which counts the orders
-- as placed.
-- Rebuilt from orders on every run: one narrow read, and a customer cannot
-- drift from their orders, or keep a row when an order moves away.
SELECT
    -- Numbered orders have a customer.
    assumeNotNull(customer_id) AS customer_id,
    toDate(min(order_time), '{{ var("shopify_timezone") }}') AS first_order_date,
    toDate(max(order_time), '{{ var("shopify_timezone") }}') AS last_order_date,
    count() AS number_of_orders,
    sum(net_total) AS net_total
FROM {{ ref('orders') }}
WHERE customer_order_number IS NOT NULL
GROUP BY customer_id
{{ shopify_query_settings() }}
