{{ config(materialized='table', order_by='(event_date, event_id)') }}
-- One row per sales event, as the store's reports count sales over time
-- (WooCommerce Analytics, under the settings dbt_project.yml repeats): an
-- order at the time the reports date it by (orders.order_time), and each of
-- its refunds at the time it was made, whichever the date type. Orders the
-- reports leave out have no events, and neither do their refunds: in
-- Analytics a refund takes its order's status, and its order's date of
-- each type turns into the refund's own (seen on the test store). A
-- cancelled order is left out by its status, as WooCommerce has no
-- cancellation of its own to date; a store that counts cancelled orders
-- in its reports gets them here whole.
-- Rebuilt from orders and refunds on every run: two narrow reads, and the
-- events cannot drift from the orders they come from.
SELECT
    concat('order-', toString(order_id)) AS event_id,
    'order' AS event_type,
    order_id,
    order_date AS event_date,
    order_time AS event_time,
    total AS amount
FROM {{ ref('orders') }}
WHERE in_sales_reports
UNION ALL
SELECT
    concat('refund-', toString(refund_id)) AS event_id,
    'refund' AS event_type,
    order_id,
    refund_date AS event_date,
    refund_time AS event_time,
    -refunded_amount AS amount
FROM {{ ref('refunds') }}
WHERE order_id IN (SELECT order_id FROM {{ ref('orders') }} WHERE in_sales_reports)
