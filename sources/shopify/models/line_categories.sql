{{ config(materialized='view') }}
-- One row per line of an order (order_lines.sql) and each category of its
-- product (product_categories_all.sql), parents included where the
-- store's categories nest, with the line's units and amounts: a line in
-- two categories counts in both, as the store's reports count it. A line
-- whose product has no category, is deleted or is no product has one row
-- without a category. A view: the categories are the product's current
-- ones, so a change of the catalog moves every past line at once, with
-- nothing to rebuild.
SELECT
    l.line_id AS line_id,
    c.category AS category,
    c.category_path AS category_path,
    -- The product is in the category itself, not only in one under it.
    ifNull(c.is_direct, true) AS is_direct,
    l.quantity AS quantity,
    l.current_quantity AS current_quantity,
    l.line_total AS line_total,
    l.returned_quantity AS returned_quantity,
    l.returned_amount AS returned_amount
FROM {{ ref('order_lines') }} AS l
LEFT JOIN (
    SELECT product_id, toNullable(category) AS category, toNullable(category_path) AS category_path,
           toNullable(is_direct) AS is_direct
    FROM {{ ref('product_categories_all') }}
) AS c ON c.product_id = l.product_id
