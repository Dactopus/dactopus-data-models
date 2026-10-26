{{ config(materialized='table', order_by='(product_id, category_path)') }}
-- One row per product and its category, the product type the owner gives
-- it (productType), as it is now: the grouping Shopify's reports call
-- "Type (category)". A type has no subcategories, so each row is the
-- product's own category, and its path is its name. A product without a
-- type has no row; a deleted product neither, its sales have no category.
-- Gift cards keep theirs: product_categories and line_categories take the
-- products they need.
SELECT
    id AS product_id,
    product_type AS category,
    product_type AS category_path,
    true AS is_direct
FROM {{ shopify_latest('products', 'id', select='id, product_type, deleted_at, updated_at, loaded_at') }}
WHERE deleted_at IS NULL AND product_type != ''
{{ shopify_query_settings() }}
