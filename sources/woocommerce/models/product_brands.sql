{{ config(materialized='view') }}
-- One row per product of the catalog (products.sql) and each of its
-- brands (product_brands_all.sql).
SELECT product_id, brand
FROM {{ ref('product_brands_all') }}
WHERE product_id IN (SELECT product_id FROM {{ ref('products') }})
