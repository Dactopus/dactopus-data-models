{{ config(materialized='table', order_by='product_id') }}
-- One row per product of the catalog, sold or not, in its current state
-- (input.sql): posts of type product, their variations apart, as
-- WooCommerce's products list counts them. A product deleted for good is
-- gone, and one in the trash is too: the list leaves the trash out of
-- All. Rebuilt whole at every run: the catalog is small next to the
-- orders, and the date of a product's last sale changes with every order.
WITH
-- The latest day each product sold on, in the store's time zone: lines
-- of orders the reports count, not cancelled (the reports leave cancelled
-- orders out by default). A refunded order still sold. A line names its
-- product, not the variation (_product_id). A line has no date of its
-- own, so every counted order is joined: a hash join holds them all in
-- memory, 250 to 380 MB for 4 million orders; partial_merge, set below,
-- 60 to 70 MB in the same time (#42).
sold AS MATERIALIZED (
    SELECT l.product_id AS product_id, toNullable(max(o.order_date)) AS last_sold_date
    FROM {{ ref('order_lines') }} AS l
    INNER JOIN {{ ref('orders') }} AS o ON o.order_id = l.order_id
    WHERE o.in_sales_reports AND NOT o.is_cancelled AND l.product_id IS NOT NULL
    GROUP BY product_id
)
SELECT
    p.product_id AS product_id,
    -- The product's name as it is now; a line keeps the name it sold under.
    p.title AS title,
    -- The post's status (https://developer.wordpress.org/advanced-administration/wordpress/post-status/):
    -- active when published, for anyone to buy; draft for draft, pending
    -- review and future (scheduled); archived for private, which only the
    -- store's staff see. NULL for a status a plugin adds.
    multiIf(p.status = 'publish', 'active', p.status IN ('draft', 'pending', 'future'), 'draft',
            p.status = 'private', 'archived', NULL) AS status,
    s.last_sold_date AS last_sold_date
FROM {{ woocommerce_products() }} AS p
LEFT JOIN sold AS s ON s.product_id = p.product_id
WHERE p.status != 'trash'
{{ woocommerce_query_settings() }}, join_algorithm = 'partial_merge'
