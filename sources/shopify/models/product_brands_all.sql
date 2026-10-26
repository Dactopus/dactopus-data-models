{{ config(materialized='table', order_by='(product_id, brand)') }}
-- One row per product and its brand, the vendor as it is now: "the
-- manufacturer, wholesaler, or other vendor", which Shopify's reports
-- group by. The store's own name is a vendor too. A product without a
-- vendor has no row; a deleted product neither.
SELECT
    id AS product_id,
    vendor AS brand
FROM {{ shopify_latest('products', 'id', select='id, vendor, deleted_at, updated_at, loaded_at') }}
WHERE deleted_at IS NULL AND vendor != ''
{{ shopify_query_settings() }}
