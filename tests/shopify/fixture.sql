-- Hand-written Shopify rows for check_numbers.py, loaded into the package
-- input (sources/shopify/input.sql). Each order is a case the package must
-- get right; check_numbers.py derives the expected numbers from these rows.
-- The input database is the query parameter db, as in input.sql.
--
-- The shop is in America/New_York (UTC-4 from August to October) and sells
-- in USD. Customers 1 and 2 order more than once; guests have no customer.
-- The shapes follow orders placed on a development store: a line's
-- discount_allocated includes its share of order-level discounts, a refund
-- line's subtotal is net of that share, and with taxes included the line's
-- tax is inside its original_total.
--
-- Every version of an order adds up. total_price is sum(original_total -
-- discount_allocated) + shipping, + tax unless taxes are included.
-- total_discounts is sum(discount_allocated), total_refunded the sum of its
-- refunds. Lines carry their order's updated_at, refund lines their
-- refund's (input.sql).

INSERT INTO {db:Identifier}.orders VALUES
-- (id, name, created_at, processed_at, updated_at, cancelled_at, closed_at, test,
--  customer_id, email, currency_code, presentment_currency_code,
--  display_financial_status, display_fulfillment_status, source_name, taxes_included,
--  total_price, total_discounts, total_shipping_price, total_tax, total_refunded, current_total_price,
--  discount_codes, shipping_country_code, shipping_province_code, shipping_city, shipping_zip)

-- 1001: customer 1's first order; paid and shipped, which closes it.
(1001, '#1001', '2026-08-10 15:00:00', '2026-08-10 15:00:00', '2026-08-11 09:00:00', NULL, '2026-08-11 09:00:00', false,
 1, 'alice@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 110, 0, 10, 0, 0, 110, [], 'US', 'NY', 'New York', '10001'),

-- 1002: a guest, unpaid (manual payment pending), no shipping address.
-- processed_at is a second before created_at, as the store shows.
(1002, '#1002', '2026-08-20 15:00:01', '2026-08-20 15:00:00', '2026-08-20 15:00:01', NULL, NULL, false,
 NULL, NULL, 'USD', 'USD', 'PENDING', 'UNFULFILLED', 'web', false,
 80, 0, 0, 0, 0, 80, [], NULL, NULL, NULL, NULL),

-- 1003: customer 2's first order, a download: payment authorized but not
-- captured (unpaid), nothing to ship (fulfilled). Placed at 22:00 on
-- August 31 in New York, which is September 1 in UTC: an August order.
(1003, '#1003', '2026-09-01 02:00:00', '2026-09-01 02:00:00', '2026-09-01 02:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'AUTHORIZED', 'FULFILLMENT_NOT_REQUIRED', 'web', false,
 30, 0, 0, 0, 0, 30, [], NULL, NULL, NULL, NULL),

-- 1004: a line discount of 10 on the hoodie, then FALL10 takes 10% off the
-- order (19), allocated 9 and 10 in proportion to the lines after their own
-- discounts (90 and 100). One of the two T-shirts refunded on October 3,
-- a month after the order: 50 less its half of the 10 allocated = 45.
(1004, '#1004', '2026-09-05 15:00:00', '2026-09-05 15:00:00', '2026-10-03 15:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'USD', 'PARTIALLY_REFUNDED', 'UNFULFILLED', 'web', false,
 181, 29, 10, 0, 45, 136, ['FALL10'], 'US', 'NY', 'New York', '10001'),

-- 1005: customer 2 cancels a paid order three hours later; Shopify refunds
-- it in the same action ("Order canceled"). Between customer 2's first and
-- second orders, it is not one of their orders in sequence.
(1005, '#1005', '2026-09-08 15:00:00', '2026-09-08 15:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', false,
 2, 'bob@example.com', 'USD', 'USD', 'REFUNDED', 'UNFULFILLED', 'web', false,
 60, 0, 0, 0, 60, 0, [], 'CA', 'ON', 'Toronto', 'M5V 2T6'),

-- 1006: fully refunded, shipping included, without cancelling. The refund
-- (210) is more than its refunded line (200): shipping is refunded outside
-- the lines. Toronto without a province code, as the store returns it.
(1006, '#1006', '2026-09-10 15:00:00', '2026-09-10 15:00:00', '2026-09-12 15:00:00', NULL, '2026-09-12 15:00:00', false,
 2, 'bob@example.com', 'USD', 'USD', 'REFUNDED', 'UNFULFILLED', 'web', false,
 210, 0, 10, 0, 210, 0, [], 'CA', NULL, 'Toronto', 'M5V 2T6'),

-- 1007: 10% tax added on top of prices (100 + 20 -> 12); shipping not
-- taxed. One of two lines shipped. The gift wrap is a custom item: no
-- product, variant or SKU.
(1007, '#1007', '2026-09-15 15:00:00', '2026-09-15 15:00:00', '2026-09-16 15:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'USD', 'PAID', 'PARTIALLY_FULFILLED', 'web', false,
 137, 0, 5, 12, 0, 137, [], 'US', 'NY', 'New York', '10001'),

-- 1008: 13% tax included in prices (Ontario HST); the customer paid in CAD,
-- amounts are the shop's USD. Imported with processed_at September 28,
-- created October 2: a September order. SEPT10 takes 10% off: 11.30 and
-- 5.65, tax included. Line tax on what is left: 101.70 * 13/113 = 11.70,
-- 50.85 * 13/113 = 5.85. Without tax the lines are 113 - 11.30 - 11.70 =
-- 90 and 56.50 - 5.65 - 5.85 = 45, which is the order's 167.55 - 15
-- shipping - 17.55 tax = 135.
(1008, '#1008', '2026-10-02 10:00:00', '2026-09-28 15:00:00', '2026-10-02 10:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'CAD', 'PAID', 'UNFULFILLED', 'dactopus-import', true,
 167.55, 16.95, 15, 17.55, 0, 167.55, ['SEPT10'], 'CA', 'ON', 'Toronto', 'M5V 2T6'),

-- 1009: a test order (Bogus Gateway), refunded the next day. Neither the
-- order, its line nor its refund count anywhere. Its 10 T-shirts would
-- top the SKU ranking if they did.
(1009, '#1009', '2026-09-20 15:00:00', '2026-09-20 15:00:00', '2026-09-21 15:00:00', NULL, '2026-09-21 15:00:00', true,
 1, 'alice@example.com', 'USD', 'USD', 'REFUNDED', 'UNFULFILLED', 'web', false,
 500, 0, 0, 0, 500, 0, [], 'US', 'NY', 'New York', '10001'),

-- 1010: a guest's unpaid order, cancelled before payment: the
-- authorization is voided and nothing is refunded. Placed (revenue) but
-- not sold (net revenue). current_quantity and current_total_price 0
-- after the cancel are not yet seen on the store.
(1010, '#1010', '2026-09-25 15:00:00', '2026-09-25 15:00:00', '2026-09-25 18:00:00', '2026-09-25 18:00:00', '2026-09-25 18:00:00', false,
 NULL, NULL, 'USD', 'USD', 'VOIDED', 'UNFULFILLED', 'web', false,
 70, 0, 10, 0, 0, 0, [], 'US', 'CA', 'San Francisco', '94103'),

-- 1011: customer 2's third order (1005 was cancelled), the only one in
-- October; fulfillment on hold.
(1011, '#1011', '2026-10-02 15:00:00', '2026-10-02 15:00:00', '2026-10-02 15:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'ON_HOLD', 'web', false,
 50, 0, 10, 0, 0, 50, [], 'CA', 'ON', 'Toronto', 'M5V 2T6');

INSERT INTO {db:Identifier}.order_lines VALUES
-- (id, order_id, order_updated_at, product_id, variant_id, sku, title, variant_title, quantity, current_quantity,
--  original_unit_price, original_total, discount_allocated, total_tax, taxable, requires_shipping, is_gift_card)
(11,  1001, '2026-08-11 09:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  2,  50,    100,   0,     0,     true,  true,  false),
(21,  1002, '2026-08-20 15:00:01', 102, 1021, 'MUG',     'Mug',         NULL,  1,  1,  80,    80,    0,     0,     true,  true,  false),
(31,  1003, '2026-09-01 02:00:00', 103, 1031, 'EBOOK',   'Field guide', 'PDF', 1,  1,  30,    30,    0,     0,     false, false, false),
(41,  1004, '2026-10-03 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   19,    0,     true,  true,  false),
(42,  1004, '2026-10-03 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  1,  50,    100,   10,    0,     true,  true,  false),
(51,  1005, '2026-09-08 18:00:00', 105, 1051, 'CAP',     'Cap',         NULL,  1,  0,  60,    60,    0,     0,     true,  true,  false),
(61,  1006, '2026-09-12 15:00:00', 106, 1061, 'JACKET',  'Jacket',      'L',   1,  0,  200,   200,   0,     0,     true,  true,  false),
(71,  1007, '2026-09-16 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   0,     10,    true,  true,  false),
(72,  1007, '2026-09-16 15:00:00', NULL, NULL, NULL,     'Gift wrap',   NULL,  1,  1,  20,    20,    0,     2,     true,  false, false),
(81,  1008, '2026-10-02 10:00:00', 107, 1071, 'BLANKET', 'Blanket',     NULL,  1,  1,  113,   113,   11.30, 11.70, true,  true,  false),
(82,  1008, '2026-10-02 10:00:00', 102, 1021, 'MUG',     'Mug',         NULL,  1,  1,  56.50, 56.50, 5.65,  5.85,  true,  true,  false),
(91,  1009, '2026-09-21 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   10, 0,  50,    500,   0,     0,     true,  true,  false),
(101, 1010, '2026-09-25 18:00:00', 105, 1051, 'CAP',     'Cap',         NULL,  1,  0,  60,    60,    0,     0,     true,  true,  false),
(111, 1011, '2026-10-02 15:00:00', 108, 1081, 'SOCKS',   'Socks',       NULL,  2,  2,  20,    40,    0,     0,     true,  true,  false);

INSERT INTO {db:Identifier}.refunds VALUES
-- (id, order_id, created_at, updated_at, note, total_refunded)
(501, 1004, '2026-10-03 15:00:00', '2026-10-03 15:00:00', '',              45),
(502, 1005, '2026-09-08 18:00:00', '2026-09-08 18:00:00', 'Order canceled', 60),
(503, 1006, '2026-09-12 15:00:00', '2026-09-12 15:00:00', '',              210),
(504, 1009, '2026-09-21 15:00:00', '2026-09-21 15:00:00', '',              500);

INSERT INTO {db:Identifier}.refund_lines VALUES
-- (refund_id, refund_updated_at, line_item_id, quantity, subtotal, total_tax, restock_type)
-- Nothing had shipped: CANCEL, as the store sets it; a cancel's refund is NO_RESTOCK.
(501, '2026-10-03 15:00:00', 42, 1,  45,  0, 'CANCEL'),
(502, '2026-09-08 18:00:00', 51, 1,  60,  0, 'NO_RESTOCK'),
(503, '2026-09-12 15:00:00', 61, 1,  200, 0, 'CANCEL'),
(504, '2026-09-21 15:00:00', 91, 10, 500, 0, 'CANCEL');

-- Earlier and repeated loads. The rows above are each order's latest
-- version; these were delivered too, and none of them may change a number.
-- Separate statements, as separate loads are: a ReplacingMergeTree input
-- would collapse duplicates within one insert.

-- 1004 as loaded on September 5, before its refund: paid, both T-shirts
-- still there. The refund on October 3 delivered the version above.
INSERT INTO {db:Identifier}.orders VALUES
(1004, '#1004', '2026-09-05 15:00:00', '2026-09-05 15:00:00', '2026-09-05 15:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'USD', 'PAID', 'UNFULFILLED', 'web', false,
 181, 29, 10, 0, 0, 181, ['FALL10'], 'US', 'NY', 'New York', '10001');

INSERT INTO {db:Identifier}.order_lines VALUES
(41,  1004, '2026-09-05 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   19,    0,     true,  true,  false),
(42,  1004, '2026-09-05 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  2,  50,    100,   10,    0,     true,  true,  false);

-- 1011 and 1006's refund delivered again unchanged, as a rerun of a load
-- does.
INSERT INTO {db:Identifier}.orders VALUES
(1011, '#1011', '2026-10-02 15:00:00', '2026-10-02 15:00:00', '2026-10-02 15:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'ON_HOLD', 'web', false,
 50, 0, 10, 0, 0, 50, [], 'CA', 'ON', 'Toronto', 'M5V 2T6');

INSERT INTO {db:Identifier}.order_lines VALUES
(111, 1011, '2026-10-02 15:00:00', 108, 1081, 'SOCKS',   'Socks',       NULL,  2,  2,  20,    40,    0,     0,     true,  true,  false);

INSERT INTO {db:Identifier}.refunds VALUES
(503, 1006, '2026-09-12 15:00:00', '2026-09-12 15:00:00', '',              210);

INSERT INTO {db:Identifier}.refund_lines VALUES
(503, '2026-09-12 15:00:00', 61, 1,  200, 0, 'CANCEL');
