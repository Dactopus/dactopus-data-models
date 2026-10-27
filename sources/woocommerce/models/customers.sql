{{ config(materialized='table', order_by='customer_id') }}
-- One row per customer with an order WooCommerce Analytics' report of new
-- and returning customers counts: the orders numbered in
-- orders.customer_order_number, every status but the excluded ones, an
-- order on hold included, paid or not. Customers are those of orders.sql:
-- accounts, guests by email, and a guest's order without an email on its
-- own. A registered account without such an order has no row.
-- Dates are those of the numbered orders, by date placed in the store's
-- time zone, as the numbering goes; an order is reported by another date
-- where woocommerce_date_type says so. net_total is what the customer's
-- numbered orders earned after refunds, as the Customers report's total
-- spend counts it: an order on hold counts there, though not in the
-- reports' net sales.
-- Rebuilt from orders on every run: one narrow read, and a customer cannot
-- drift from their orders, or keep a row when an order moves away.
SELECT
    -- Numbered orders have a customer.
    assumeNotNull(customer_id) AS customer_id,
    toDate(min(placed_time), '{{ var("woocommerce_timezone") }}') AS first_order_date,
    toDate(max(placed_time), '{{ var("woocommerce_timezone") }}') AS last_order_date,
    count() AS number_of_orders,
    sum(net_total) AS net_total
FROM {{ ref('orders') }}
WHERE customer_order_number IS NOT NULL
GROUP BY customer_id
{{ woocommerce_query_settings() }}
