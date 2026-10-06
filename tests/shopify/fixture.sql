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
-- tax is inside its original_total. Shapes not yet seen on the store are
-- marked so.
--
-- Every version of an order adds up. total_price is sum(original_total -
-- discount_allocated) + shipping_price, + total_tax unless taxes are
-- included, + total_duties + total_additional_fees; total_tax is the lines'
-- tax + shipping_tax + the tax on duties; total_refunded is the sum of its
-- refunds. Lines carry their order's updated_at, refund
-- lines their refund's (input.sql).
--
-- A load inserts orders, lines, refunds and refund lines one table after
-- another, so their loaded_at differ by a second or so within one load.
-- First comes a load between 1005's cancel and its refund, then the load
-- on October 4 that delivered each order's latest version, then earlier
-- and repeated loads: no number may depend on the order rows arrive in.

-- 1005 as a load read it a second after 18:00:00, between the cancel and
-- the refund made in the same second: cancelled, still paid, the cap not
-- yet refunded, no refund. Its updated_at equals the final version's; only
-- the later loaded_at tells the final version apart. Were this version
-- read, the financial status would be paid and one more item would be
-- left (items_net). The intermediate state is not yet seen on the store.
INSERT INTO {db:Identifier}.orders VALUES
(1005, '#1005', '2026-09-08 15:00:00', '2026-09-08 15:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'UNFULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-09-08 18:00:01');

INSERT INTO {db:Identifier}.order_lines VALUES
(51,  1005, '2026-09-08 18:00:00', 105, 1051, 'CAP',     'Cap',         NULL,  1,  1,  60,    60,    0,     0,     0,     true,  true,  false, '2026-09-08 18:00:02');

-- The load on October 4: each order's latest version.
INSERT INTO {db:Identifier}.orders VALUES
-- (id, name, created_at, processed_at, updated_at, cancelled_at, closed_at, test,
--  customer_id, email, currency_code, presentment_currency_code,
--  display_financial_status, display_fulfillment_status, source_name, taxes_included,
--  total_price, shipping_price, shipping_tax, total_tax, total_refunded, current_total_price, total_tip,
--  total_duties, total_additional_fees, discount_codes, shipping_country_code, shipping_province_code, shipping_city, shipping_zip, loaded_at)

-- 1001: customer 1's first order; paid and shipped, which closes it. A 25
-- gift card bought with it is inside the total but is not a sale, as on
-- the development store (#1016): sales 110, not 135. The gift card is
-- refunded on August 20, a refund line on its line, as on the store
-- (#1016): 25 paid back, yet none of the 110 sold, so net 110, not 85.
(1001, '#1001', '2026-08-10 15:00:00', '2026-08-10 15:00:00', '2026-08-20 15:00:00', NULL, '2026-08-11 09:00:00', false,
 1, 'alice@example.com', 'USD', 'USD', 'PARTIALLY_REFUNDED', 'FULFILLED', 'web', false,
 135, 10, 0, 0, 25, 110, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),

-- 1002: a guest, unpaid (manual payment pending), no shipping address.
-- processed_at is a second before created_at, as the store shows.
(1002, '#1002', '2026-08-20 15:00:01', '2026-08-20 15:00:00', '2026-08-20 15:00:01', NULL, NULL, false,
 NULL, NULL, 'USD', 'USD', 'PENDING', 'UNFULFILLED', 'web', false,
 80, 0, 0, 0, 0, 80, 0, 0, 0, [], NULL, NULL, NULL, NULL, '2026-10-04 00:00:00'),

-- 1003: customer 2's first order, a download: payment authorized but not
-- captured before the provider's deadline (EXPIRED, voided). Nothing to ship, yet the store shows it unfulfilled
-- (#1013 on the development store). A custom item, as on the store: no
-- product, no tax and nothing to ship, like a tip, yet a sale. Placed at 22:00 on August 31 in New
-- York, which is September 1 in UTC: an August order.
(1003, '#1003', '2026-09-01 02:00:00', '2026-09-01 02:00:00', '2026-09-01 02:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'EXPIRED', 'UNFULFILLED', 'web', false,
 30, 0, 0, 0, 0, 30, 0, 0, 0, [], NULL, NULL, NULL, NULL, '2026-10-04 00:00:00'),

-- 1004: a line discount of 10 on the hoodie, then FALL10 takes 10% off the
-- order (19), allocated 9 and 10 in proportion to the lines after their own
-- discounts (90 and 100). One of the two T-shirts refunded on October 3,
-- a month after the order: 50 less its half of the 10 allocated = 45.
(1004, '#1004', '2026-09-05 15:00:00', '2026-09-05 15:00:00', '2026-10-03 15:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'USD', 'PARTIALLY_REFUNDED', 'UNFULFILLED', 'web', false,
 181, 10, 0, 0, 45, 136, 0, 0, 0, ['FALL10'], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),

-- 1005: customer 2 cancels a paid order three hours later; Shopify refunds
-- it in the same action ("Order canceled"). Between customer 2's first and
-- second orders, it is not one of their orders in sequence. An earlier load
-- read it between the cancel and the refund, with the same updated_at
-- (below).
(1005, '#1005', '2026-09-08 15:00:00', '2026-09-08 15:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', '2026-09-08 18:00:00', false,
 2, 'bob@example.com', 'USD', 'USD', 'REFUNDED', 'UNFULFILLED', 'web', false,
 60, 0, 0, 0, 60, 0, 0, 0, 0, [], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-10-04 00:00:00'),

-- 1006: fully refunded, shipping included, without cancelling. The refund
-- (210) is more than its refunded line (200): shipping is refunded outside
-- the lines. Refunded at 22:00 on September 30 in New York, October 1 in
-- UTC: a September refund. Toronto without a province code, as the store
-- returns it. Loaded through API 2026-10, which shows an order with
-- nothing left to fulfill as FULFILLMENT_NOT_REQUIRED, not UNFULFILLED
-- (#1003 on the development store); 1010 shows the older value.
(1006, '#1006', '2026-09-10 15:00:00', '2026-09-10 15:00:00', '2026-10-01 02:00:00', NULL, '2026-10-01 02:00:00', false,
 2, 'bob@example.com', 'USD', 'USD', 'REFUNDED', 'FULFILLMENT_NOT_REQUIRED', 'web', false,
 210, 10, 0, 0, 210, 0, 0, 0, 0, [], 'CA', NULL, 'Toronto', 'M5V 2T6', '2026-10-04 00:00:00'),

-- 1007: 10% tax added on top of prices (100 + 20 -> 12); shipping not
-- taxed. One of two lines shipped. The gift wrap is a custom item: no
-- product, variant or SKU. A 10% tip on the 120 of lines, 12, untaxed, is
-- inside the total and comes as a line "Tip", as on the development store
-- (#1017); it is not a sale: total 149, sales 137.
(1007, '#1007', '2026-09-15 15:00:00', '2026-09-15 15:00:00', '2026-09-16 15:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'USD', 'PAID', 'PARTIALLY_FULFILLED', 'web', false,
 149, 5, 0, 12, 0, 149, 12, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),

-- 1008: 13% tax included in prices (Ontario HST); the customer paid in CAD,
-- amounts are the shop's USD. Imported with processed_at September 12,
-- created October 2: a September order, and customer 1's third order by
-- processed_at, before 1007 (September 15); by created_at it would be
-- the fourth. SEPT10 takes 10% off:
-- 11.30 and 5.65, tax included; 10 and 5 without (113 / 1.13 = 100 less
-- the line's 90, 56.50 / 1.13 = 50 less 45). Line tax on what is left: 101.70 * 13/113
-- = 11.70, 50.85 * 13/113 = 5.85. Shipping 16.95 is taxed too, 1.95
-- inside, and total_tax counts it, as on the development store (#1015:
-- 113 + 16.95 = 129.95, tax 13 + 1.95). Without tax the lines are 113 -
-- 11.30 - 11.70 = 90 and 56.50 - 5.65 - 5.85 = 45 and shipping 15, which
-- is the order's 169.50 - 19.50 tax = 150.
(1008, '#1008', '2026-10-02 10:00:00', '2026-09-12 15:00:00', '2026-10-02 10:00:00', NULL, NULL, false,
 1, 'alice@example.com', 'USD', 'CAD', 'PAID', 'UNFULFILLED', 'dactopus-import', true,
 169.50, 16.95, 1.95, 19.50, 0, 169.50, 0, 0, 0, ['SEPT10'], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-10-04 00:00:00'),

-- 1009: a test order (Bogus Gateway), refunded the next day. Neither the
-- order, its line nor its refund count anywhere. Its 10 T-shirts would
-- top the SKU ranking if they did.
(1009, '#1009', '2026-09-20 15:00:00', '2026-09-20 15:00:00', '2026-09-21 15:00:00', NULL, '2026-09-21 15:00:00', true,
 1, 'alice@example.com', 'USD', 'USD', 'REFUNDED', 'UNFULFILLED', 'web', false,
 500, 0, 0, 0, 500, 0, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),

-- 1010: a guest's unpaid order, cancelled before payment: the
-- authorization is voided and nothing is refunded. Placed (revenue) but
-- not sold (net revenue). current_quantity and current_total_price 0
-- after the cancel are not yet seen on the store.
(1010, '#1010', '2026-09-25 15:00:00', '2026-09-25 15:00:00', '2026-09-25 18:00:00', '2026-09-25 18:00:00', '2026-09-25 18:00:00', false,
 NULL, NULL, 'USD', 'USD', 'VOIDED', 'UNFULFILLED', 'web', false,
 70, 10, 0, 0, 0, 0, 0, 0, 0, [], 'US', 'CA', 'San Francisco', '94103', '2026-10-04 00:00:00'),

-- 1011: customer 2's third order (1005 was cancelled), the only one in
-- October; fulfillment on hold. FREESHIP takes the 10 shipping off, so
-- shipping_price is 0, as on the development store (#1014).
(1011, '#1011', '2026-10-02 15:00:00', '2026-10-02 15:00:00', '2026-10-02 15:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'ON_HOLD', 'web', false,
 40, 0, 0, 0, 0, 40, 0, 0, 0, ['FREESHIP'], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-10-04 00:00:00'),

-- 1012: a guest in Toronto pays import duties at checkout, as on the
-- development store (#1019, the same amounts): two T-shirts 190, shipping
-- 16.95 with 2.20 tax, duties 34.20 with 4.45 tax, 13% on the T-shirts
-- 24.70. The duties and their tax are inside the total, 272.50, and not
-- goods: the lines make 272.50 - 16.95 - 31.35 - 34.20 = 190.
(1012, '#1012', '2026-10-03 16:00:00', '2026-10-03 16:00:00', '2026-10-03 16:00:00', NULL, NULL, false,
 NULL, NULL, 'USD', 'USD', 'PAID', 'UNFULFILLED', 'web', false,
 272.50, 16.95, 2.20, 31.35, 0, 272.50, 0, 34.20, 0, [], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-10-04 00:00:00');

INSERT INTO {db:Identifier}.order_lines VALUES
-- (id, order_id, order_updated_at, product_id, variant_id, sku, title, variant_title, quantity, current_quantity,
--  original_unit_price, original_total, discount_allocated, total_tax, tax_rate, taxable, requires_shipping, is_gift_card, loaded_at)
(11,  1001, '2026-08-20 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  2,  50,    100,   0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(12,  1001, '2026-08-20 15:00:00', 109, 1091, NULL,      'Gift Card',   '$25', 1,  0,  25,    25,    0,     0,     0,     false, false, true,  '2026-10-04 00:00:01'),
(21,  1002, '2026-08-20 15:00:01', 102, 1021, 'MUG',     'Mug',         NULL,  1,  1,  80,    80,    0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(31,  1003, '2026-09-01 02:00:00', NULL, NULL, 'EBOOK',   'Field guide', 'PDF', 1,  1,  30,    30,    0,     0,     0,     false, false, false, '2026-10-04 00:00:01'),
(41,  1004, '2026-10-03 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   19,    0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(42,  1004, '2026-10-03 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  1,  50,    100,   10,    0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(51,  1005, '2026-09-08 18:00:00', 105, 1051, 'CAP',     'Cap',         NULL,  1,  0,  60,    60,    0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(61,  1006, '2026-10-01 02:00:00', 106, 1061, 'JACKET',  'Jacket',      'L',   1,  0,  200,   200,   0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(71,  1007, '2026-09-16 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   0,     10,    0.10,  true,  true,  false, '2026-10-04 00:00:01'),
(72,  1007, '2026-09-16 15:00:00', NULL, NULL, NULL,     'Gift wrap',   NULL,  1,  1,  20,    20,    0,     2,     0.10,  true,  false, false, '2026-10-04 00:00:01'),
(73,  1007, '2026-09-16 15:00:00', NULL, NULL, NULL,     'Tip',         NULL,  1,  1,  12,    12,    0,     0,     0,     false, false, false, '2026-10-04 00:00:01'),
(81,  1008, '2026-10-02 10:00:00', 107, 1071, 'BLANKET', 'Blanket',     NULL,  1,  1,  113,   113,   11.30, 11.70, 0.13,  true,  true,  false, '2026-10-04 00:00:01'),
(82,  1008, '2026-10-02 10:00:00', 102, 1021, 'MUG',     'Mug',         NULL,  1,  1,  56.50, 56.50, 5.65,  5.85,  0.13,  true,  true,  false, '2026-10-04 00:00:01'),
(91,  1009, '2026-09-21 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   10, 0,  50,    500,   0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(101, 1010, '2026-09-25 18:00:00', 105, 1051, 'CAP',     'Cap',         NULL,  1,  0,  60,    60,    0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(111, 1011, '2026-10-02 15:00:00', 108, 1081, 'SOCKS',   'Socks',       NULL,  2,  2,  20,    40,    0,     0,     0,     true,  true,  false, '2026-10-04 00:00:01'),
(121, 1012, '2026-10-03 16:00:00', 110, 1101, 'TEE-COTTON', 'Cotton T-shirt', NULL, 2, 2, 95,  190,   0,     24.70, 0.13,  true,  true,  false, '2026-10-04 00:00:01');

INSERT INTO {db:Identifier}.refunds VALUES
-- (id, order_id, created_at, updated_at, note, total_refunded, loaded_at)
(505, 1001, '2026-08-20 15:00:00', '2026-08-20 15:00:00', '',               25,  '2026-10-04 00:00:02'),
(501, 1004, '2026-10-03 15:00:00', '2026-10-03 15:00:00', '',               45,  '2026-10-04 00:00:02'),
(502, 1005, '2026-09-08 18:00:00', '2026-09-08 18:00:00', 'Order canceled', 60,  '2026-10-04 00:00:02'),
(503, 1006, '2026-10-01 02:00:00', '2026-10-01 02:00:00', '',               210, '2026-10-04 00:00:02'),
(504, 1009, '2026-09-21 15:00:00', '2026-09-21 15:00:00', '',               500, '2026-10-04 00:00:02');

INSERT INTO {db:Identifier}.refund_lines VALUES
-- (id, refund_id, refund_updated_at, line_item_id, quantity, subtotal, total_tax, restock_type, loaded_at)
-- Nothing had shipped: CANCEL, as the store sets it; a cancel's refund is NO_RESTOCK.
-- The gift card was delivered: RETURN, as on the store (#1016).
(5051, 505, '2026-08-20 15:00:00', 12, 1,  25,  0, 'RETURN',     '2026-10-04 00:00:03'),
(5011, 501, '2026-10-03 15:00:00', 42, 1,  45,  0, 'CANCEL',     '2026-10-04 00:00:03'),
(5021, 502, '2026-09-08 18:00:00', 51, 1,  60,  0, 'NO_RESTOCK', '2026-10-04 00:00:03'),
(5031, 503, '2026-10-01 02:00:00', 61, 1,  200, 0, 'CANCEL',     '2026-10-04 00:00:03'),
(5041, 504, '2026-09-21 15:00:00', 91, 10, 500, 0, 'CANCEL',     '2026-10-04 00:00:03');

-- Earlier and repeated loads, delivered too; none of them may change a
-- number.

-- 1004 as loaded on September 5, before its refund: paid, both T-shirts
-- still there, and placed for customer 2. The store then moved it to
-- customer 1 (orderCustomerSet, which changes updated_at on the
-- development store), and the refund on October 3 delivered the version
-- above. Were this version read, customer 2 would have five orders.
INSERT INTO {db:Identifier}.orders VALUES
(1004, '#1004', '2026-09-05 15:00:00', '2026-09-05 15:00:00', '2026-09-05 15:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'UNFULFILLED', 'web', false,
 181, 10, 0, 0, 0, 181, 0, 0, 0, ['FALL10'], 'US', 'NY', 'New York', '10001', '2026-09-05 16:00:00');

INSERT INTO {db:Identifier}.order_lines VALUES
(41,  1004, '2026-09-05 15:00:00', 104, 1041, 'HOODIE',  'Hoodie',      'M',   1,  1,  100,   100,   19,    0,     0,     true,  true,  false, '2026-09-05 16:00:01'),
(42,  1004, '2026-09-05 15:00:00', 101, 1011, 'TEE-M',   'T-shirt',     'M',   2,  2,  50,    100,   10,    0,     0,     true,  true,  false, '2026-09-05 16:00:01');

-- 1011 and 1006's refund delivered again unchanged, as a rerun of a load
-- does.
INSERT INTO {db:Identifier}.orders VALUES
(1011, '#1011', '2026-10-02 15:00:00', '2026-10-02 15:00:00', '2026-10-02 15:00:00', NULL, NULL, false,
 2, 'bob@example.com', 'USD', 'USD', 'PAID', 'ON_HOLD', 'web', false,
 40, 0, 0, 0, 0, 40, 0, 0, 0, ['FREESHIP'], 'CA', 'ON', 'Toronto', 'M5V 2T6', '2026-10-04 06:00:00');

INSERT INTO {db:Identifier}.order_lines VALUES
(111, 1011, '2026-10-02 15:00:00', 108, 1081, 'SOCKS',   'Socks',       NULL,  2,  2,  20,    40,    0,     0,     0,     true,  true,  false, '2026-10-04 06:00:01');

INSERT INTO {db:Identifier}.refunds VALUES
(503, 1006, '2026-10-01 02:00:00', '2026-10-01 02:00:00', '',               210, '2026-10-04 06:00:02');

INSERT INTO {db:Identifier}.refund_lines VALUES
(5031, 503, '2026-10-01 02:00:00', 61, 1,  200, 0, 'CANCEL',     '2026-10-04 06:00:03');
