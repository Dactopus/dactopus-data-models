{{ config(materialized='view') }}
-- One row per order (orders.sql) and each discount code used on it
-- (orders.discount_codes, Shopify's discountCodes), with the order's customer and
-- amounts: an order with two codes counts under both, an order without a
-- code has no row. arrayDistinct keeps the key, the order and the code,
-- unique whatever the source lists. A view, as line_categories.
SELECT
    source_id AS source_id,
    order_id AS order_id,
    arrayJoin(arrayDistinct(discount_codes)) AS discount_code,
    in_sales_reports AS in_sales_reports,
    customer_id AS customer_id,
    total AS total,
    discount_total AS discount_total
FROM {{ ref('orders') }}
