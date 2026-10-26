{{ config(materialized='table', order_by='product_id') }}
-- One row per product of the catalog, sold or not: the latest version of
-- each product (input.sql). A deleted product is gone; so are gift cards,
-- which are no goods (order_lines.sql). Rebuilt whole at every run: the
-- catalog is small next to the orders, and the date of a product's last
-- sale changes with every order.
WITH
latest AS (
    SELECT id, title, status, is_gift_card, deleted_at
    FROM {{ shopify_latest('products', 'id', select='id, title, status, is_gift_card, deleted_at, updated_at, loaded_at') }}
),
-- The latest day each product sold on, in the shop's time zone: lines of
-- orders not cancelled. A refunded order still sold. A line carries its
-- order's date, and orders and order_lines hold the same orders, so only
-- the few orders left out are looked up: a join with every order would
-- hold all of them in memory at every run, 200 to 340 MB for 4 million.
sold AS (
    SELECT product_id, toNullable(max(order_date)) AS last_sold_date
    FROM {{ ref('order_lines') }}
    WHERE product_id IS NOT NULL
      AND order_id NOT IN (SELECT order_id FROM {{ ref('orders') }} WHERE NOT in_sales_reports OR is_cancelled)
    GROUP BY product_id
)
SELECT
    p.id AS product_id,
    -- The product's name as it is now; a line keeps the name it sold under.
    p.title AS title,
    -- ProductStatus (https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus):
    -- active when a customer can buy it, UNLISTED too (sold through a
    -- link, hidden from search and collections); draft; archived. NULL
    -- for a status Shopify adds later.
    multiIf(p.status IN ('ACTIVE', 'UNLISTED'), 'active', p.status = 'DRAFT', 'draft',
            p.status = 'ARCHIVED', 'archived', NULL) AS status,
    s.last_sold_date AS last_sold_date
FROM latest AS p
LEFT JOIN sold AS s ON s.product_id = p.id
WHERE p.deleted_at IS NULL AND NOT p.is_gift_card
{{ shopify_query_settings() }}
