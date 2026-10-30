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
    sum(net_total) AS net_total,
    -- Retention windows: whether the customer's second order came within N
    -- days of the first (orders.days_since_previous_order of the second),
    -- NULL until the window is over: its last day, the first order's date
    -- + N, ended before the day of the last load of orders, the latest
    -- synced_at of the orders built. A clock by today would move the windows
    -- with no new data, and an incremental run over unchanged input would
    -- change the table.
{%- for n in [30, 60, 90, 365] %}
    if(first_order_date + {{ n }} < last_load_date,
       ifNull(minIf(days_since_previous_order, customer_order_number = 2) <= {{ n }}, false),
       NULL) AS second_order_within_{{ n }}_days{{ ',' if not loop.last }}
{%- endfor %}
FROM {{ ref('orders') }}
CROSS JOIN (SELECT toDate(max(synced_at), '{{ var("woocommerce_timezone") }}') AS last_load_date FROM {{ ref('orders') }}) AS clock
WHERE customer_order_number IS NOT NULL
GROUP BY customer_id, last_load_date
{{ woocommerce_query_settings() }}
