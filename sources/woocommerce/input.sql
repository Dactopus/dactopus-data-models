-- Input of the WooCommerce package: the store's own order tables, copied
-- from its MySQL database into ClickHouse by change data capture (CDC).
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
-- https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/includes/class-wc-install.php.
--
-- Each table is a log of versions. CDC appends a row for every insert,
-- update and delete in MySQL, with
--   _peerdb_version     larger for a later change of the same row;
--   _peerdb_is_deleted  1 when the row was deleted, with its last values;
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
    status String,                   -- wc-processing, wc-completed, ...; trash without the prefix
    currency String,                 -- the order's currency
    type String,                     -- shop_order, shop_order_refund
    tax_amount Decimal(26, 8),       -- tax on goods only (cart_tax); shipping tax is in operational data
    total_amount Decimal(26, 8),     -- order total; a refund's is negative
    customer_id UInt64,              -- 0 for a guest
    billing_email String,
    date_created_gmt DateTime64(6),  -- UTC
    parent_order_id UInt64,          -- a refund's order
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
    created_via String,                     -- checkout, store-api, admin, rest-api, ...
    prices_include_tax Bool,
    date_paid_gmt DateTime64(6),            -- UTC; empty until paid
    date_completed_gmt DateTime64(6),       -- UTC; empty until completed
    shipping_total_amount Decimal(26, 8),   -- without tax
    shipping_tax_amount Decimal(26, 8),
    discount_total_amount Decimal(26, 8),   -- coupons, without tax
    discount_tax_amount Decimal(26, 8),
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
    address_type String,  -- billing, shipping
    city String,          -- as typed
    state String,         -- the store's code for it, such as NY
    postcode String,
    country String,       -- two-letter code
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
    meta_key String,
    meta_value String,
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
    order_item_name String,  -- the product's name as it was on the order
    order_item_type String,
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
    meta_key String,
    meta_value String,
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
    sku String,  -- '' when the product has none
    _peerdb_synced_at DateTime64(9),
    _peerdb_is_deleted UInt8,
    _peerdb_version UInt64
)
ENGINE = MergeTree
ORDER BY (product_id, _peerdb_version);
