{{ config(materialized='table', order_by='(product_id, brand)') }}
-- One row per product and each of its brands (product_brand, a taxonomy of
-- WooCommerce's core, checked on 11.2.1) as they are now. Brands may nest as
-- categories do; a product counts in the brands it is given, not in the
-- ones above them: WooCommerce has no report by brand to follow. Products
-- in the trash keep their brands, as their categories.
WITH
links AS MATERIALIZED (
    SELECT * FROM {{ woocommerce_product_terms('product_brand') }}
)
SELECT DISTINCT l.product_id AS product_id, n.name AS brand
FROM links AS l
INNER JOIN {{ woocommerce_term_names('(SELECT term_id FROM links)') }} AS n ON n.term_id = l.term_id
{{ woocommerce_query_settings() }}
