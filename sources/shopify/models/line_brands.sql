{{ config(materialized='view') }}
-- One row per line of an order (order_lines.sql) and each brand of its
-- product (product_brands_all.sql), with the line's units and amounts: a
-- line of a product with two brands counts in both. A line whose product
-- has no brand, is deleted or is no product has one row without a brand.
-- A view, as line_categories.
SELECT
    l.line_id AS line_id,
    b.brand AS brand,
    l.quantity AS quantity,
    l.current_quantity AS current_quantity,
    l.line_total AS line_total,
    l.returned_quantity AS returned_quantity,
    l.returned_amount AS returned_amount
FROM {{ ref('order_lines') }} AS l
LEFT JOIN (
    SELECT product_id, toNullable(brand) AS brand FROM {{ ref('product_brands_all') }}
) AS b ON b.product_id = l.product_id
