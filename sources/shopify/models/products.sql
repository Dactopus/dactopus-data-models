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
-- orders not cancelled. A refunded order still sold.
sold AS (
    SELECT l.product_id AS product_id, toNullable(max(o.order_date)) AS last_sold_date
    FROM {{ ref('order_lines') }} AS l
    INNER JOIN {{ ref('orders') }} AS o ON o.order_id = l.order_id
    WHERE o.in_sales_reports AND NOT o.is_cancelled AND l.product_id IS NOT NULL
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
