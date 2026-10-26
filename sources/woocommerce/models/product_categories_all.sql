{{ config(materialized='table', order_by='(product_id, category_path)') }}
-- One row per product and each of its categories (product_cat) as they
-- are now, and every category above them: categories nest, and a product
-- in T-Shirts, under Clothing, is in Clothing too, as WooCommerce
-- Analytics' filter by category takes it (input.sql). is_direct marks the
-- categories the product is in itself, the ones Analytics' Categories
-- report counts it in. A product in a category and in one under it has
-- one row for the parent, direct. Products in the trash keep their
-- categories, and so do their sales: line_categories and
-- product_categories take the products they need.
WITH
links AS MATERIALIZED (
    SELECT * FROM {{ woocommerce_product_terms('product_cat') }}
),
-- Every category, for the parents of the products' ones.
tree AS MATERIALIZED (
    SELECT term_id, ifNull(parent, 0) AS parent
    FROM {{ woocommerce_current('term_taxonomy', 'term_taxonomy_id', "taxonomy = 'product_cat'") }}
),
names AS MATERIALIZED (
    SELECT * FROM {{ woocommerce_term_names('(SELECT term_id FROM tree)') }}
),
-- Each category and every category above it, itself at depth 0.
-- WordPress keeps the tree without cycles; the depth bounds it anyway.
ancestors AS (
    WITH RECURSIVE up AS (
        SELECT term_id, term_id AS ancestor_id, parent AS next_id, 0 AS depth FROM tree
        UNION ALL
        SELECT up.term_id, t.term_id, t.parent, up.depth + 1
        FROM up INNER JOIN tree AS t ON t.term_id = up.next_id
        WHERE up.next_id != 0 AND up.depth < 100
    )
    SELECT term_id, ancestor_id, depth FROM up
),
-- A category's names from the top down, as WooCommerce shows its parents:
-- Clothing > T-Shirts. Two categories may share a name under different
-- parents; their paths differ.
paths AS MATERIALIZED (
    SELECT a.term_id AS term_id,
           arrayStringConcat(arrayMap(x -> x.2, arrayReverseSort(x -> x.1, groupArray((a.depth, n.name)))), ' > ') AS path
    FROM ancestors AS a
    INNER JOIN names AS n ON n.term_id = a.ancestor_id
    GROUP BY a.term_id
)
SELECT
    l.product_id AS product_id,
    any(n.name) AS category,
    any(p.path) AS category_path,
    max(a.depth = 0) = 1 AS is_direct
FROM links AS l
INNER JOIN ancestors AS a ON a.term_id = l.term_id
INNER JOIN names AS n ON n.term_id = a.ancestor_id
INNER JOIN paths AS p ON p.term_id = a.ancestor_id
GROUP BY l.product_id, a.ancestor_id
{{ woocommerce_query_settings() }}
