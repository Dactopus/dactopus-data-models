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
    sum(net_total) AS net_total,
    -- Retention windows: whether the customer's second order came within N
    -- days of the first (orders.days_since_previous_order of the second),
    -- NULL until the window is over: its last day, the first order's date
    -- + N, ended before the day of the last load of orders, the latest
    -- loaded_at of the orders built. A clock by today would move the windows
    -- with no new data, and an incremental run over unchanged input would
    -- change the table.
{%- for n in [30, 60, 90, 365] %}
    if(first_order_date + {{ n }} < last_load_date,
       ifNull(minIf(days_since_previous_order, customer_order_number = 2) <= {{ n }}, false),
       NULL) AS second_order_within_{{ n }}_days{{ ',' if not loop.last }}
{%- endfor %}
FROM {{ ref('orders') }}
CROSS JOIN (SELECT toDate(max(loaded_at), '{{ var("shopify_timezone") }}') AS last_load_date FROM {{ ref('orders') }}) AS clock
WHERE customer_order_number IS NOT NULL
GROUP BY customer_id, last_load_date
{{ shopify_query_settings() }}
