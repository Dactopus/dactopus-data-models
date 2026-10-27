-- Input of the Shopify package: five flat tables, filled from the GraphQL
-- Admin API (https://shopify.dev/docs/api/admin-graphql/latest) by any
-- loader. Only the columns the package reads; the comment on each names the
-- GraphQL field it comes from. Any transport may deliver more columns; it
-- must deliver these.
--
-- Checked on API version 2026-10; earlier versions differ only in
-- display_fulfillment_status (below).
--
-- Ids are the numeric legacyResourceId, not the gid:// string. Amounts are
-- in the shop's currency (the shopMoney half of a MoneyBag), so they add up
-- across orders whatever currency the customer paid in. Times are UTC.
--
-- The tables are a log of versions. A loader appends what the API returns:
-- each load of the orders updated since the last one adds the whole order
-- again, its lines and refunds included. Delivering the same version twice
-- is harmless; the package reads the latest version of each order (by
-- updated_at) and of each refund. A line has no time of its own, so it
-- carries its order's updated_at, and the package takes the lines of the
-- latest version of the order.
--
-- updated_at has whole seconds, so two loads can deliver different
-- versions with the same updated_at: one load reads an order between two
-- changes made in the same second (a cancel and its refund), the next
-- reads it again. loaded_at breaks the tie: of two versions with the same
-- updated_at, the later load wins. ClickHouse fills it at insert time, so
-- a loader that names its columns need not send it; the tables are
-- separate inserts, so an order and its lines get different loaded_at.
-- The package therefore takes the lines with the order's latest
-- order_updated_at and of each line its latest load, never lines whose
-- loaded_at equals the order's.
-- An incremental build rereads what was loaded since its last run by
-- loaded_at, so rows may arrive in any order of updated_at (a loader
-- catching up, a backfill); a loader that sends loaded_at must send the
-- time of the insert, not an older one.
--
-- The tables keep every version, and the package does not depend on the
-- engine. A deployment may collapse old versions to save space with
-- ReplacingMergeTree(<version>) ORDER BY <key>: orders (updated_at) by id,
-- order_lines (order_updated_at) by (order_id, id), refunds (updated_at)
-- by (order_id, id), refund_lines (refund_updated_at) by (refund_id, id),
-- products (updated_at) by id.
-- Merges run when ClickHouse chooses, so the package still picks the
-- latest version itself, reading each table in the order of its sorting
-- key below, as a stream; a table with another sorting key gives the
-- same rows, sorted whole in memory (macros/shopify.sql).
--
-- The database is a query parameter, the package's shopify_input_database:
--   clickhouse client --param_db=shopify_raw --multiquery < input.sql
CREATE DATABASE IF NOT EXISTS {db:Identifier};

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/Order
CREATE TABLE IF NOT EXISTS {db:Identifier}.orders
(
    id UInt64,                                  -- legacyResourceId
    name String,                                -- '#1001', what the customer sees
    created_at DateTime('UTC'),                 -- createdAt
    -- processedAt: "the date that appears on your orders and that's used in
    -- the analytic reports"; an import may set it in the past
    -- (https://shopify.dev/docs/api/admin-graphql/latest/input-objects/OrderCreateOrderInput).
    processed_at DateTime('UTC'),
    -- updatedAt, "when the order was last modified"; a refund and a
    -- fulfillment change it (seen on a development store).
    updated_at DateTime('UTC'),
    cancelled_at Nullable(DateTime('UTC')),     -- cancelledAt
    closed_at Nullable(DateTime('UTC')),        -- closedAt
    test Bool,                                  -- test
    customer_id Nullable(UInt64),               -- customer.legacyResourceId; NULL for a guest
    email Nullable(String),                     -- email
    currency_code String,                       -- currencyCode, the shop's currency
    presentment_currency_code Nullable(String), -- presentmentCurrencyCode, the customer's
    display_financial_status String,            -- displayFinancialStatus
    -- displayFulfillmentStatus. From API 2026-10, FULFILLMENT_NOT_REQUIRED
    -- for an order with nothing left to fulfill (cancelled or refunded whole
    -- before shipping); earlier versions return UNFULFILLED for it.
    display_fulfillment_status String,
    source_name Nullable(String),               -- sourceName: web, pos, or an app's id
    taxes_included Bool,                        -- taxesIncluded
    total_price Decimal(18, 4),                 -- totalPriceSet, before refunds
    -- Sum of shippingLines.discountedPriceSet: after shipping discounts (a
    -- free-shipping code included, as of API 2024-07), tax inside when
    -- taxesIncluded. totalShippingPriceSet is not used: it is before
    -- shipping discounts, and totalDiscountsSet includes them (a
    -- free-shipping order on a development store: 10, 10, and 0 here).
    -- https://shopify.dev/docs/api/admin-graphql/latest/objects/ShippingLine
    shipping_price Decimal(18, 4),
    shipping_tax Decimal(18, 4),                -- sum of shippingLines.taxLines.priceSet
    total_tax Decimal(18, 4),                   -- totalTaxSet, before refunds; lines, shipping and duties
    total_refunded Decimal(18, 4),              -- totalRefundedSet, duties refunded included
    current_total_price Decimal(18, 4),         -- currentTotalPriceSet, after refunds
    -- totalTipReceivedSet. A tip is inside total_price and comes as a line
    -- of its own, "Tip": no product, not taxable, nothing to ship (#1017 on
    -- the development store).
    total_tip Decimal(18, 4),
    -- originalTotalDutiesSet: import duties collected at checkout (Shopify
    -- Markets), inside total_price, with their tax inside total_tax (#1019
    -- on the development store: 190 of goods + 16.95 shipping + 34.20
    -- duties + 31.35 tax, 4.45 of it on the duties, = 272.50). 0 when the
    -- API returns null: no duties.
    total_duties Decimal(18, 4),
    -- originalTotalAdditionalFeesSet: other import fees, 0 when null. Not
    -- yet seen on the store; taken to be inside total_price as duties are,
    -- as Shopify's reports add both to total sales
    -- (https://shopify.dev/docs/api/shopifyql/latest/schemas/sales_revenue/sales:
    -- total_sales = net sales + additional fees + duties + shipping + taxes).
    total_additional_fees Decimal(18, 4),
    discount_codes Array(String),               -- discountCodes
    shipping_country_code Nullable(String),     -- shippingAddress.countryCodeV2
    shipping_province_code Nullable(String),    -- shippingAddress.provinceCode
    shipping_city Nullable(String),             -- shippingAddress.city
    shipping_zip Nullable(String),              -- shippingAddress.zip
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row (header)
)
ENGINE = MergeTree
ORDER BY (id, updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/LineItem
CREATE TABLE IF NOT EXISTS {db:Identifier}.order_lines
(
    id UInt64,                                  -- legacy id from the gid
    order_id UInt64,
    order_updated_at DateTime('UTC'),           -- the updated_at of the order this line came with
    product_id Nullable(UInt64),                -- product.legacyResourceId; NULL for a custom item
    variant_id Nullable(UInt64),                -- variant.legacyResourceId
    sku Nullable(String),                       -- sku
    title Nullable(String),                     -- title
    variant_title Nullable(String),             -- variantTitle
    quantity UInt32,                            -- quantity, as ordered
    current_quantity UInt32,                    -- currentQuantity, after refunds and edits
    original_unit_price Decimal(18, 4),         -- originalUnitPriceSet
    original_total Decimal(18, 4),              -- originalTotalSet; tax inside when taxesIncluded
    -- Sum of discountAllocations.allocatedAmountSet: the line's own discount
    -- and its share of order-level discounts. discountedTotalSet "doesn't
    -- include order-level discounts", so it is not used.
    discount_allocated Decimal(18, 4),
    total_tax Decimal(18, 4),                   -- sum of taxLines.priceSet
    tax_rate Decimal(9, 6),                     -- sum of taxLines.rate, 0.13 for 13%
    taxable Bool,                               -- taxable
    requires_shipping Bool,                     -- requiresShipping
    is_gift_card Bool,                          -- isGiftCard: a gift card sold, inside total_price
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row (header)
)
ENGINE = MergeTree
ORDER BY (order_id, id, order_updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/Refund
CREATE TABLE IF NOT EXISTS {db:Identifier}.refunds
(
    id UInt64,                                  -- legacyResourceId
    order_id UInt64,
    created_at DateTime('UTC'),                 -- createdAt, when the refund was recorded
    -- processedAt, "when the refund was processed": the date Shopify's
    -- sales reports count it on. Equal to createdAt for a refund made in the
    -- admin; an import sets it in the past (RefundInput.processedAt,
    -- https://shopify.dev/docs/api/admin-graphql/latest/input-objects/RefundInput),
    -- and createdAt is then the day of the import (#45, seen on a
    -- development store).
    processed_at DateTime('UTC'),
    updated_at DateTime('UTC'),                 -- updatedAt
    note Nullable(String),                      -- note
    -- totalRefundedSet: lines, shipping, duties and adjustments, with their
    -- tax (suggestedRefund of one of #1019's two T-shirts with its duty on
    -- the development store: 95 + 12.35 tax + 17.10 duty + 2.23 its tax =
    -- 126.68).
    total_refunded Decimal(18, 4),
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row (header)
)
ENGINE = MergeTree
ORDER BY (order_id, id, updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/RefundLineItem
-- One row per refund line, keyed by its own id and the version. A refund can
-- hold several lines of one line item: Shopify returns two for a line
-- restocked at two locations (suggestedRefund on a development store).
CREATE TABLE IF NOT EXISTS {db:Identifier}.refund_lines
(
    id UInt64,                                  -- legacy id from the gid
    refund_id UInt64,
    refund_updated_at DateTime('UTC'),          -- the updated_at of the refund this line came with
    line_item_id UInt64,                        -- lineItem, legacy id from the gid
    quantity UInt32,                            -- quantity
    subtotal Decimal(18, 4),                    -- subtotalSet, net of the line's discounts
    total_tax Decimal(18, 4),                   -- totalTaxSet
    restock_type String,                        -- restockType: CANCEL, NO_RESTOCK, RETURN, LEGACY_RESTOCK
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row (header)
)
ENGINE = MergeTree
ORDER BY (refund_id, id, refund_updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/Product
-- Every product of the store, sold or not: archived ones and drafts
-- included. A load of the products updated since the last one adds each of
-- them again, as for orders. A deleted product is gone from the API; the
-- loader learns of it from the store's events (events, action destroy,
-- subjectType PRODUCT:
-- https://shopify.dev/docs/api/admin-graphql/latest/queries/events) or by
-- reloading every product and finding it missing, and adds a version with
-- deleted_at and updated_at both at the time of the deletion. The package
-- drops a product whose latest version has deleted_at; it reads nothing
-- else of that version, so a loader that knows only the id sends the other
-- columns empty.
CREATE TABLE IF NOT EXISTS {db:Identifier}.products
(
    id UInt64,                                  -- legacyResourceId
    title String,                               -- title, as it is now
    -- productType: the owner's own grouping of products, free text; '' when
    -- not set (the field is a non-null String). Shopify's reports group
    -- sales by it as the product's "Type (category)".
    product_type String,
    -- vendor: "the manufacturer, wholesaler, or other vendor". It can be
    -- the store's own name: 9 of the development store's 18 products had it.
    vendor String,
    status String,                              -- status: ACTIVE, ARCHIVED, DRAFT, UNLISTED
    is_gift_card Bool,                          -- isGiftCard
    updated_at DateTime('UTC'),                 -- updatedAt; the time of the deletion for a deleted product
    deleted_at Nullable(DateTime('UTC')),       -- the event's createdAt; NULL while the product exists
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row (header)
)
ENGINE = MergeTree
ORDER BY (id, updated_at);
