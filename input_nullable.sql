-- Input of the WooCommerce package: the store's own order tables, and
-- WordPress's tables of its products and their categories and brands,
-- copied from its MySQL database into ClickHouse by change data capture
-- (CDC).
-- WooCommerce 8.2 and later keeps orders in these tables (High-Performance
-- Order Storage, HPOS:
-- https://developer.woocommerce.com/docs/features/high-performance-order-storage/).
-- A store still on the legacy posts storage turns on HPOS compatibility
-- mode, which keeps these tables in sync (README).
--
-- Only the columns the package reads; the CDC copy may hold more. Names
-- and types are those PeerDB gives a MySQL table (checked with PeerDB 0.37
-- over MySQL 8.4; ClickPipes runs PeerDB, not checked): bigint unsigned as UInt64,
-- decimal(26,8) as Decimal(26, 8), datetime as DateTime64(6) without a
-- time zone (the *_gmt columns hold UTC), tinyint(1) as Bool, text as
-- String. The schema of each table:
-- https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/src/Internal/DataStores/Orders/OrdersTableDataStore.php
-- (get_database_schema) and
-- https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/includes/class-wc-install.php,
-- and of WordPress's own tables:
-- https://github.com/WordPress/wordpress-develop/blob/trunk/src/wp-admin/includes/schema.php
-- (wp_get_db_schema).
--
-- Each table is a log of versions. CDC appends a row for every insert,
-- update and delete in MySQL, with
--   _peerdb_version     larger for a later change of the same row,
--   _peerdb_is_deleted  1 when the row was deleted, with its last values,
--   _peerdb_synced_at   when the row reached ClickHouse.
-- The package takes the latest version of each row and drops it when that
-- version is a delete. PeerDB writes ReplacingMergeTree(_peerdb_version)
-- tables; the package does not depend on the engine or on FINAL.
--
-- Empty values. By default PeerDB writes no Nullable columns: a NULL in
-- MySQL arrives as the type's default (1970-01-01 00:00:00 for a time, 0,
-- ''). With PEERDB_NULLABLE on, the same columns are Nullable and keep
-- NULL. The package reads both the same way.
--
-- Table names keep the store's prefix, wp_ by default, and the package's
-- woocommerce_table_prefix names it. This file creates wp_ tables; for
-- another prefix, replace it in the text:
--   sed 's/wp_/wp_2_/g' input.sql | clickhouse client --param_db=woocommerce_raw --multiquery
-- The database is a query parameter, the package's
-- woocommerce_input_database:
--   clickhouse client --param_db=woocommerce_raw --multiquery < input.sql
CREATE DATABASE IF NOT EXISTS {db:Identifier};

-- Orders and refunds, one row each (type shop_order or shop_order_refund).
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_wc_orders
(
    id UInt64,
    status Nullable(String),                   -- wc-processing, wc-completed, ...; trash without the prefix
    currency Nullable(String),                 -- the order's currency
    type Nullable(String),                     -- shop_order, shop_order_refund
    tax_amount Nullable(Decimal(26, 8)),       -- tax on goods only (cart_tax); shipping tax is in operational data
    total_amount Nullable(Decimal(26, 8)),     -- order total; a refund's is negative
    customer_id Nullable(UInt64),              -- 0 for a guest
    billing_email Nullable(String),
    date_created_gmt Nullable(DateTime64(6)),  -- UTC
    parent_order_id Nullable(UInt64),          -- a refund's order
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (id, _peerdb_version);

-- One row per order or refund.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_wc_order_operational_data
(
    id UInt64,
    order_id UInt64,
    created_via Nullable(String),                     -- checkout, store-api, admin, rest-api, ...
    prices_include_tax Nullable(Bool),
    date_paid_gmt Nullable(DateTime64(6)),            -- UTC; empty until paid
    date_completed_gmt Nullable(DateTime64(6)),       -- UTC; empty until completed
    shipping_total_amount Nullable(Decimal(26, 8)),   -- without tax
    shipping_tax_amount Nullable(Decimal(26, 8)),
    discount_total_amount Nullable(Decimal(26, 8)),   -- coupons, without tax
    discount_tax_amount Nullable(Decimal(26, 8)),
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (id, _peerdb_version);

-- Billing and shipping address of an order (address_type).
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_wc_order_addresses
(
    id UInt64,
    order_id UInt64,
    address_type Nullable(String),  -- billing, shipping
    city Nullable(String),          -- as typed
    state Nullable(String),         -- the store's code for it, such as NY
    postcode Nullable(String),
    country Nullable(String),       -- two-letter code
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (id, _peerdb_version);

-- Key-value data of an order. The package reads only the order number a
-- plugin keeps (woocommerce_order_number_meta_key) and the exchange rates
-- of multi-currency plugins.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_wc_orders_meta
(
    id UInt64,
    order_id UInt64,
    meta_key Nullable(String),
    meta_value Nullable(String),
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (id, _peerdb_version);

-- Items of orders and refunds: line_item (goods), shipping, fee, coupon,
-- tax. A refund's items belong to the refund's id and carry negative
-- quantities and amounts.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_woocommerce_order_items
(
    order_item_id UInt64,
    order_item_name Nullable(String),  -- the product's name as it was on the order
    order_item_type Nullable(String),
    order_id UInt64,
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (order_item_id, _peerdb_version);

-- Key-value data of an item: _product_id, _variation_id, _qty,
-- _line_subtotal, _line_total (after discounts, without tax, not rounded),
-- _line_tax; _fee_amount of a fee; _refunded_item_id of a refund's item.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_woocommerce_order_itemmeta
(
    meta_id UInt64,
    order_item_id UInt64,
    meta_key Nullable(String),
    meta_value Nullable(String),
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (meta_id, _peerdb_version);

-- Products, for the SKU: an order line does not keep it, so the line gets
-- its product's current SKU; a deleted product has none.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_wc_product_meta_lookup
(
    product_id Int64,
    sku Nullable(String),  -- '' when the product has none
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (product_id, _peerdb_version);

-- Posts of every kind: products (post_type product) and their variations
-- (product_variation), and also pages, revisions and, with HPOS, a
-- placeholder of each order (shop_order_placehold). The CDC copy needs none
-- of the text columns (post_content, post_excerpt, post_content_filtered,
-- to_ping, pinged, post_password). An order line names the product in
-- _product_id and its variation in _variation_id
-- (WC_Order_Item_Product::set_product).
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_posts
(
    ID UInt64,
    post_title Nullable(String),   -- the product's name as it is now
    post_status Nullable(String),  -- publish, draft, pending, private, future, trash, ...
    post_type Nullable(String),
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (ID, _peerdb_version);

-- Product categories, brands and tags are terms of a taxonomy
-- (https://developer.wordpress.org/plugins/taxonomies/): the term's name in
-- wp_terms, its taxonomy in wp_term_taxonomy, the products it is on in
-- wp_term_relationships. A product is linked to term_taxonomy_id, not to
-- term_id: the two come from counters of their own and can differ.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_terms
(
    term_id UInt64,
    name Nullable(String),  -- as the owner typed it; one name can be in several taxonomies (Uncategorized)
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (term_id, _peerdb_version);

-- Categories nest: parent names the parent category. WooCommerce
-- Analytics (checked on 11.2.1) counts a sale in the categories its product
-- is in, not in their parents: the Categories report groups by the
-- product's own terms (Admin/API/Reports/Categories/DataStore.php). Its
-- filter by category, in the Products, Orders and Revenue reports, also
-- takes the products of the subcategories: it finds them with
-- wc_get_products, whose tax query includes child terms by default
-- (Admin/API/Reports/DataStore.php, get_products_by_cat_ids).
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_term_taxonomy
(
    term_taxonomy_id UInt64,
    term_id UInt64,
    taxonomy Nullable(String),  -- product_cat, product_brand (in the core, checked on 11.2.1), product_tag, ...
    parent Nullable(UInt64),    -- the parent's term_id, not its term_taxonomy_id; 0 at the top
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (term_taxonomy_id, _peerdb_version);

-- One row per term on a post: a product in two categories has two. Keyed
-- by both columns.
CREATE TABLE IF NOT EXISTS {db:Identifier}.wp_term_relationships
(
    object_id UInt64,         -- the product's ID
    term_taxonomy_id UInt64,
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (object_id, term_taxonomy_id, _peerdb_version);
