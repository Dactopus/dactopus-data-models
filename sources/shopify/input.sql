-- Input of the Shopify package: four flat tables, filled from the GraphQL
-- Admin API (https://shopify.dev/docs/api/admin-graphql/latest) by any
-- loader. Only the columns the package reads; the comment on each names the
-- GraphQL field it comes from. Any transport may deliver more columns; it
-- must deliver these.
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
-- latest version of the order. The tables keep every version; a deployment
-- may use ReplacingMergeTree on the same keys to collapse old ones.
-- The database is a query parameter, the package's shopify_input_database:
--   clickhouse client --param_db=shopify_raw --multiquery < input.sql
CREATE DATABASE IF NOT EXISTS {db:Identifier};

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/Order
CREATE TABLE IF NOT EXISTS {db:Identifier}.orders
(
    id UInt64,                                  -- legacyResourceId
    name String,                                -- '#1001', what the customer sees
    created_at DateTime('UTC'),                 -- createdAt
    processed_at DateTime('UTC'),               -- processedAt, the date Shopify reports use
    updated_at DateTime('UTC'),                 -- updatedAt; changes on refund, cancel, fulfillment
    cancelled_at Nullable(DateTime('UTC')),     -- cancelledAt
    closed_at Nullable(DateTime('UTC')),        -- closedAt
    test Bool,                                  -- test
    customer_id Nullable(UInt64),               -- customer.legacyResourceId; NULL for a guest
    email Nullable(String),                     -- email
    currency_code String,                       -- currencyCode, the shop's currency
    presentment_currency_code Nullable(String), -- presentmentCurrencyCode, the customer's
    display_financial_status String,            -- displayFinancialStatus
    display_fulfillment_status String,          -- displayFulfillmentStatus
    source_name Nullable(String),               -- sourceName: web, pos, or an app's id
    taxes_included Bool,                        -- taxesIncluded
    total_price Decimal(18, 4),                 -- totalPriceSet, before refunds
    total_discounts Decimal(18, 4),             -- totalDiscountsSet
    total_shipping_price Decimal(18, 4),        -- totalShippingPriceSet
    total_tax Decimal(18, 4),                   -- totalTaxSet
    total_refunded Decimal(18, 4),              -- totalRefundedSet
    current_total_price Decimal(18, 4),         -- currentTotalPriceSet, after refunds
    discount_codes Array(String),               -- discountCodes
    shipping_country_code Nullable(String),     -- shippingAddress.countryCodeV2
    shipping_province_code Nullable(String),    -- shippingAddress.provinceCode
    shipping_city Nullable(String),             -- shippingAddress.city
    shipping_zip Nullable(String)               -- shippingAddress.zip
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
    -- and its share of order-level discounts. discountedTotalSet leaves the
    -- order-level share out, so it is not used.
    discount_allocated Decimal(18, 4),
    total_tax Decimal(18, 4),                   -- sum of taxLines.priceSet
    taxable Bool,                               -- taxable
    requires_shipping Bool,                     -- requiresShipping
    is_gift_card Bool                           -- isGiftCard
)
ENGINE = MergeTree
ORDER BY (order_id, id, order_updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/Refund
CREATE TABLE IF NOT EXISTS {db:Identifier}.refunds
(
    id UInt64,                                  -- legacyResourceId
    order_id UInt64,
    created_at DateTime('UTC'),                 -- createdAt, the date of the refund
    updated_at DateTime('UTC'),                 -- updatedAt
    note Nullable(String),                      -- note
    total_refunded Decimal(18, 4)               -- totalRefundedSet: lines, shipping and adjustments
)
ENGINE = MergeTree
ORDER BY (order_id, id, updated_at);

-- https://shopify.dev/docs/api/admin-graphql/latest/objects/RefundLineItem
-- One row per refunded line in a refund, keyed by the pair and the version.
CREATE TABLE IF NOT EXISTS {db:Identifier}.refund_lines
(
    refund_id UInt64,
    refund_updated_at DateTime('UTC'),          -- the updated_at of the refund this line came with
    line_item_id UInt64,                        -- lineItem, legacy id from the gid
    quantity UInt32,                            -- quantity
    subtotal Decimal(18, 4),                    -- subtotalSet, net of the line's discounts
    total_tax Decimal(18, 4),                   -- totalTaxSet
    restock_type String                         -- restockType: CANCEL, NO_RESTOCK, RETURN, LEGACY_RESTOCK
)
ENGINE = MergeTree
ORDER BY (refund_id, line_item_id, refund_updated_at);
