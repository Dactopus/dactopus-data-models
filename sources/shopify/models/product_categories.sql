{{ config(materialized='view') }}
-- One row per product of the catalog (products.sql) and each of its
-- categories (product_categories_all.sql), parents included where the
-- store's categories nest.
SELECT product_id, category, category_path, is_direct
FROM {{ ref('product_categories_all') }}
WHERE product_id IN (SELECT product_id FROM {{ ref('products') }})
