-- A product is in a category once: a product in a category and in one
-- under it has one row for the parent, which line_categories counts once.
SELECT product_id, category_path, count() AS rows
FROM {{ ref('product_categories_all') }}
GROUP BY product_id, category_path
HAVING rows > 1
