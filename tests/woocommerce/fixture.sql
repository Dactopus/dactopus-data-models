-- Hand-designed WooCommerce orders for check_numbers.py, as change data
-- capture writes them into the package input (sources/woocommerce/input.sql):
-- every change of a row is a new version, a delete is a version with
-- _peerdb_is_deleted = 1, and empty values are the types' defaults
-- (1970-01-01 00:00:00, 0, ''), as PeerDB writes them by default. The
-- shapes follow orders placed on a local test store (WooCommerce 11.2.1).
-- The input database is the query parameter db, as in input.sql. Times are
-- written in UTC; the input's times have no time zone of their own, so each
-- insert reads them in UTC (session_timezone), whatever the server's zone.
-- check_numbers.py derives the expected numbers from these rows.
--
-- The store is in America/New_York (UTC-4 from August to October), sells in
-- USD and charges 10 % tax. Customers 1 and 2 order more than once; guests
-- have customer 0 and are told apart by their billing email, in any case:
-- 102 is customer 2's, guest4 orders twice (118, 112), and 119 has no
-- email. Store reports date an order by payment and leave out
-- pending, cancelled and failed orders, as WooCommerce Analytics does by
-- default. Products: 11 mug (MUG), 12 tee with variations 121 (TEE-M) and
-- 122 (TEE-L), 13 sticker without a SKU, 14 cap (CAP), deleted from the
-- catalogue on October 10.
--
-- Orders (total; date of payment in New York):
--   101  customer 1: 2 mugs, 1 TEE-M, shipping 10; 88, paid August 10,
--        completed. The mug's quantity was edited from 1 to 2 before
--        payment (new versions of its meta rows) and the tax item was
--        recreated (4 deleted, 5 new). A plugin's order number 1 is in
--        the order meta.
--   102  guest with customer 2's email in other case (Bob@Example.com),
--        before customer 2's first order as a customer: 3 stickers,
--        16.50, on hold (bank transfer awaited), no payment date: not in
--        the reports.
--   103  customer 2: a cap, shipping 5; 33, paid at 22:10 on August 31
--        (September 1 in UTC). The cap is deleted later: no SKU.
--   104  customer 1: 2 TEE-L with a 10 % coupon, shipping 10; 70.40,
--        placed August 30, paid September 2, completed. Refund 901 of one
--        tee, 29.70, on October 5.
--   106  guest: pending payment, 22.
--   107  customer 2: paid September 8, cancelled September 9 with
--        nothing refunded; 44. Refund 904 of one mug, 22, on September
--        10: the reports leave it out with its order.
--   108  guest: payment failed, 33.
--   109  customer 1: a mug, fees of +5 and -7, shipping 10; 30.80, paid
--        September 12, completed. A sticker line was removed before
--        payment (its item and meta rows deleted).
--   110  customer 2: prices include tax, a TEE-M at 35 with tax,
--        shipping 10; 46, paid September 15, processing. The line total
--        is 31.818182, without tax and not rounded.
--   111  customer 1: a mug, shipping 10; 33, paid September 20, refunded
--        whole with shipping on September 22 (refund 902).
--   112  guest, billing address only: 2 TEE-M; 66, paid October 1,
--        completed. Refund 903 of an amount, 5, without lines, on
--        October 2. One version of the order arrives twice.
--   113  customer 2, cash on delivery: 2 stickers, shipping 5; 16.50.
--        Processing without a payment date from October 3, completed and
--        paid on delivery on October 6.
--   114  guest: paid October 4, then moved to the trash.
--   115  a checkout draft, never placed.
--   116  guest: paid and completed October 8, then deleted for good.
--   118  guest4, before their 112: a mug; 22, on hold, never paid.
--   119  guest without an email, placed in the admin: a mug; 22, on hold,
--        never paid.
--   117  customer 1, paid in EUR through WooPayments on October 9: 2 mugs
--        45, tax 4.50, shipping 9 and its tax 0.90; 59.40 EUR. The
--        order's rate is 0.9 EUR per USD: 66 USD.

INSERT INTO {db:Identifier}.wp_wc_orders
    (id, status, currency, type, tax_amount, total_amount, customer_id, billing_email, date_created_gmt, parent_order_id, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(101, 'wc-pending', 'USD', 'shop_order', 5, 66, 1, 'alice@example.com', '2026-08-10 14:00:00', 0, '2026-08-10 14:00:05', 0, 7),
(101, 'wc-processing', 'USD', 'shop_order', 7, 88, 1, 'alice@example.com', '2026-08-10 14:00:00', 0, '2026-08-10 14:05:05', 0, 54),
(101, 'wc-completed', 'USD', 'shop_order', 7, 88, 1, 'alice@example.com', '2026-08-10 14:00:00', 0, '2026-08-12 09:00:05', 0, 56),
(102, 'wc-on-hold', 'USD', 'shop_order', 1.5, 16.5, 0, 'Bob@Example.com', '2026-08-20 15:00:00', 0, '2026-08-20 15:00:05', 0, 58),
(103, 'wc-pending', 'USD', 'shop_order', 2.5, 33, 2, 'bob@example.com', '2026-09-01 02:00:00', 0, '2026-09-01 02:00:05', 0, 75),
(103, 'wc-processing', 'USD', 'shop_order', 2.5, 33, 2, 'bob@example.com', '2026-09-01 02:00:00', 0, '2026-09-01 02:10:05', 0, 91),
(104, 'wc-on-hold', 'USD', 'shop_order', 5.4, 70.4, 1, 'alice@example.com', '2026-08-30 12:00:00', 0, '2026-08-30 12:00:05', 0, 93),
(104, 'wc-processing', 'USD', 'shop_order', 5.4, 70.4, 1, 'alice@example.com', '2026-08-30 12:00:00', 0, '2026-09-02 12:00:05', 0, 112),
(104, 'wc-completed', 'USD', 'shop_order', 5.4, 70.4, 1, 'alice@example.com', '2026-08-30 12:00:00', 0, '2026-09-04 10:00:05', 0, 114),
(901, 'wc-completed', 'USD', 'shop_order_refund', -2.7, -29.7, 0, '', '2026-10-05 14:00:00', 104, '2026-10-05 14:00:05', 0, 116),
(104, 'wc-completed', 'USD', 'shop_order', 5.4, 70.4, 1, 'alice@example.com', '2026-08-30 12:00:00', 0, '2026-10-05 14:00:05', 0, 128),
(106, 'wc-pending', 'USD', 'shop_order', 2, 22, 0, 'guest2@example.com', '2026-09-05 16:00:00', 0, '2026-09-05 16:00:05', 0, 129),
(107, 'wc-processing', 'USD', 'shop_order', 4, 44, 2, 'bob@example.com', '2026-09-08 13:00:00', 0, '2026-09-08 13:00:05', 0, 140),
(107, 'wc-cancelled', 'USD', 'shop_order', 4, 44, 2, 'bob@example.com', '2026-09-08 13:00:00', 0, '2026-09-09 09:00:05', 0, 151),
(108, 'wc-failed', 'USD', 'shop_order', 3, 33, 0, 'guest3@example.com', '2026-09-10 11:00:00', 0, '2026-09-10 11:00:05', 0, 152),
(109, 'wc-pending', 'USD', 'shop_order', 2.3, 36.3, 1, 'alice@example.com', '2026-09-12 14:50:00', 0, '2026-09-12 14:50:05', 0, 163),
(109, 'wc-processing', 'USD', 'shop_order', 1.8, 30.8, 1, 'alice@example.com', '2026-09-12 14:50:00', 0, '2026-09-12 15:00:05', 0, 207),
(109, 'wc-completed', 'USD', 'shop_order', 1.8, 30.8, 1, 'alice@example.com', '2026-09-12 14:50:00', 0, '2026-09-14 10:00:05', 0, 209),
(110, 'wc-processing', 'USD', 'shop_order', 3.18, 46, 2, 'bob@example.com', '2026-09-15 16:00:00', 0, '2026-09-15 16:00:05', 0, 211),
(111, 'wc-completed', 'USD', 'shop_order', 2, 33, 1, 'alice@example.com', '2026-09-20 10:00:00', 0, '2026-09-20 10:00:05', 0, 227),
(902, 'wc-completed', 'USD', 'shop_order_refund', -2, -33, 0, '', '2026-09-22 12:00:00', 111, '2026-09-22 12:00:05', 0, 243),
(111, 'wc-refunded', 'USD', 'shop_order', 2, 33, 1, 'alice@example.com', '2026-09-20 10:00:00', 0, '2026-09-22 12:00:05', 0, 260),
(112, 'wc-completed', 'USD', 'shop_order', 6, 66, 0, 'guest4@example.com', '2026-10-01 13:00:00', 0, '2026-10-01 13:00:05', 0, 261),
(903, 'wc-completed', 'USD', 'shop_order_refund', 0, -5, 0, '', '2026-10-02 09:00:00', 112, '2026-10-02 09:00:05', 0, 273),
(112, 'wc-completed', 'USD', 'shop_order', 6, 66, 0, 'guest4@example.com', '2026-10-01 13:00:00', 0, '2026-10-02 09:00:05', 0, 275),
(112, 'wc-completed', 'USD', 'shop_order', 6, 66, 0, 'guest4@example.com', '2026-10-01 13:00:00', 0, '2026-10-02 09:00:05', 0, 275),  -- same version delivered again
(113, 'wc-processing', 'USD', 'shop_order', 1, 16.5, 2, 'bob@example.com', '2026-10-03 14:00:00', 0, '2026-10-03 14:00:05', 0, 277),
(113, 'wc-completed', 'USD', 'shop_order', 1, 16.5, 2, 'bob@example.com', '2026-10-03 14:00:00', 0, '2026-10-06 18:00:05', 0, 293),
(114, 'wc-processing', 'USD', 'shop_order', 2, 22, 0, 'guest5@example.com', '2026-10-04 10:00:00', 0, '2026-10-04 10:00:05', 0, 295),
(114, 'trash', 'USD', 'shop_order', 2, 22, 0, 'guest5@example.com', '2026-10-04 10:00:00', 0, '2026-10-04 11:00:05', 0, 306),
(115, 'wc-checkout-draft', 'USD', 'shop_order', 2, 22, 0, '', '2026-10-07 10:00:00', 0, '2026-10-07 10:00:05', 0, 307),
(116, 'wc-processing', 'USD', 'shop_order', 2, 22, 0, 'guest6@example.com', '2026-10-08 10:00:00', 0, '2026-10-08 10:00:05', 0, 318),
(116, 'wc-completed', 'USD', 'shop_order', 2, 22, 0, 'guest6@example.com', '2026-10-08 10:00:00', 0, '2026-10-08 12:00:05', 0, 329),
(116, 'wc-completed', 'USD', 'shop_order', 2, 22, 0, 'guest6@example.com', '2026-10-08 10:00:00', 0, '2026-10-08 13:00:05', 1, 330),
(117, 'wc-processing', 'EUR', 'shop_order', 4.5, 59.4, 1, 'alice@example.com', '2026-10-09 10:00:00', 0, '2026-10-09 10:00:05', 0, 341),
(904, 'wc-completed', 'USD', 'shop_order_refund', -2, -22, 0, '', '2026-09-10 10:00:00', 107, '2026-09-10 10:00:05', 0, 360),
(107, 'wc-cancelled', 'USD', 'shop_order', 4, 44, 2, 'bob@example.com', '2026-09-08 13:00:00', 0, '2026-09-10 10:00:05', 0, 372),
(118, 'wc-on-hold', 'USD', 'shop_order', 2, 22, 0, 'guest4@example.com', '2026-09-28 14:00:00', 0, '2026-09-28 14:00:05', 0, 491),
(119, 'wc-on-hold', 'USD', 'shop_order', 2, 22, 0, '', '2026-09-30 14:00:00', 0, '2026-09-30 14:00:05', 0, 492);

INSERT INTO {db:Identifier}.wp_wc_order_operational_data
    (id, order_id, created_via, prices_include_tax, date_paid_gmt, date_completed_gmt, shipping_total_amount, shipping_tax_amount, discount_total_amount, discount_tax_amount, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 101, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-08-10 14:00:05', 0, 8),
(1, 101, 'checkout', false, '2026-08-10 14:05:00', '1970-01-01 00:00:00', 10, 1, 0, 0, '2026-08-10 14:05:05', 0, 55),
(1, 101, 'checkout', false, '2026-08-10 14:05:00', '2026-08-12 09:00:00', 10, 1, 0, 0, '2026-08-12 09:00:05', 0, 57),
(2, 102, 'store-api', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-08-20 15:00:05', 0, 59),
(3, 103, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 5, 0.5, 0, 0, '2026-09-01 02:00:05', 0, 76),
(3, 103, 'checkout', false, '2026-09-01 02:10:00', '1970-01-01 00:00:00', 5, 0.5, 0, 0, '2026-09-01 02:10:05', 0, 92),
(4, 104, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 10, 1, 6, 0.6, '2026-08-30 12:00:05', 0, 94),
(4, 104, 'checkout', false, '2026-09-02 12:00:00', '1970-01-01 00:00:00', 10, 1, 6, 0.6, '2026-09-02 12:00:05', 0, 113),
(4, 104, 'checkout', false, '2026-09-02 12:00:00', '2026-09-04 10:00:00', 10, 1, 6, 0.6, '2026-09-04 10:00:05', 0, 115),
(5, 901, '', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-05 14:00:05', 0, 117),
(6, 106, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-05 16:00:05', 0, 130),
(7, 107, 'checkout', false, '2026-09-08 13:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-08 13:00:05', 0, 141),
(8, 108, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-10 11:00:05', 0, 153),
(9, 109, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 10, 1, 0, 0, '2026-09-12 14:50:05', 0, 164),
(9, 109, 'checkout', false, '2026-09-12 15:00:00', '1970-01-01 00:00:00', 10, 1, 0, 0, '2026-09-12 15:00:05', 0, 208),
(9, 109, 'checkout', false, '2026-09-12 15:00:00', '2026-09-14 10:00:00', 10, 1, 0, 0, '2026-09-14 10:00:05', 0, 210),
(10, 110, 'checkout', true, '2026-09-15 16:00:00', '1970-01-01 00:00:00', 10, 1, 0, 0, '2026-09-15 16:00:05', 0, 212),
(11, 111, 'checkout', false, '2026-09-20 10:00:00', '2026-09-20 10:00:00', 10, 1, 0, 0, '2026-09-20 10:00:05', 0, 228),
(12, 902, '', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', -10, -1, 0, 0, '2026-09-22 12:00:05', 0, 244),
(13, 112, 'checkout', false, '2026-10-01 13:00:00', '2026-10-01 13:00:00', 0, 0, 0, 0, '2026-10-01 13:00:05', 0, 262),
(14, 903, '', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-02 09:00:05', 0, 274),
(15, 113, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 5, 0.5, 0, 0, '2026-10-03 14:00:05', 0, 278),
(15, 113, 'checkout', false, '2026-10-06 18:00:00', '2026-10-06 18:00:00', 5, 0.5, 0, 0, '2026-10-06 18:00:05', 0, 294),
(16, 114, 'checkout', false, '2026-10-04 10:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-04 10:00:05', 0, 296),
(17, 115, 'store-api', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-07 10:00:05', 0, 308),
(18, 116, 'checkout', false, '2026-10-08 10:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-08 10:00:05', 0, 319),
(18, 116, 'checkout', false, '2026-10-08 10:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-10-08 13:00:05', 1, 331),
(19, 117, 'checkout', false, '2026-10-09 10:00:00', '1970-01-01 00:00:00', 9, 0.9, 0, 0, '2026-10-09 10:00:05', 0, 342),
(20, 904, '', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-10 10:00:05', 0, 361),
(21, 118, 'checkout', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-28 14:00:05', 0, 493),
(22, 119, 'admin', false, '1970-01-01 00:00:00', '1970-01-01 00:00:00', 0, 0, 0, 0, '2026-09-30 14:00:05', 0, 494);

INSERT INTO {db:Identifier}.wp_wc_order_addresses
    (id, order_id, address_type, city, state, postcode, country, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 101, 'billing', 'New York', 'NY', '10001', 'US', '2026-08-10 14:00:05', 0, 9),
(2, 101, 'shipping', 'New York', 'NY', '10001', 'US', '2026-08-10 14:00:05', 0, 10),
(3, 102, 'shipping', 'Albany', 'NY', '10001', 'US', '2026-08-20 15:00:05', 0, 60),
(4, 103, 'shipping', 'Buffalo', 'NY', '10001', 'US', '2026-09-01 02:00:05', 0, 77),
(5, 104, 'shipping', 'new york', 'NY', '10001', 'US', '2026-08-30 12:00:05', 0, 95),
(6, 109, 'shipping', 'New York', 'NY', '10001', 'US', '2026-09-12 14:50:05', 0, 165),
(7, 110, 'shipping', 'Toronto', 'ON', 'M5V 2T6', 'CA', '2026-09-15 16:00:05', 0, 213),
(8, 111, 'shipping', 'Newark', 'NJ', '07102', 'US', '2026-09-20 10:00:05', 0, 229),
(9, 112, 'billing', 'Boston', 'MA', '02108', 'US', '2026-10-01 13:00:05', 0, 263),
(10, 113, 'shipping', 'New York', 'NY', '10001', 'US', '2026-10-03 14:00:05', 0, 279),
(11, 117, 'shipping', 'Berlin', 'BE', '10115', 'DE', '2026-10-09 10:00:05', 0, 343);

INSERT INTO {db:Identifier}.wp_wc_orders_meta
    (id, order_id, meta_key, meta_value, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 101, '_order_number', '1', '2026-08-10 14:00:05', 0, 11),
(2, 117, '_wcpay_multi_currency_order_exchange_rate', '0.9', '2026-10-09 10:00:05', 0, 344),
(3, 117, '_wcpay_multi_currency_order_default_currency', 'USD', '2026-10-09 10:00:05', 0, 345);

INSERT INTO {db:Identifier}.wp_woocommerce_order_items
    (order_item_id, order_item_name, order_item_type, order_id, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 'Mug', 'line_item', 101, '2026-08-10 14:00:05', 0, 12),
(2, 'Tee', 'line_item', 101, '2026-08-10 14:00:05', 0, 21),
(3, 'Flat rate', 'shipping', 101, '2026-08-10 14:00:05', 0, 30),
(4, 'US-TAX-1', 'tax', 101, '2026-08-10 14:00:05', 0, 34),
(4, 'US-TAX-1', 'tax', 101, '2026-08-10 14:03:05', 1, 44),
(5, 'US-TAX-1', 'tax', 101, '2026-08-10 14:03:05', 0, 49),
(6, 'Sticker', 'line_item', 102, '2026-08-20 15:00:05', 0, 61),
(7, 'US-TAX-1', 'tax', 102, '2026-08-20 15:00:05', 0, 70),
(8, 'Cap', 'line_item', 103, '2026-09-01 02:00:05', 0, 78),
(9, 'Flat rate', 'shipping', 103, '2026-09-01 02:00:05', 0, 87),
(10, 'Tee', 'line_item', 104, '2026-08-30 12:00:05', 0, 96),
(11, 'Flat rate', 'shipping', 104, '2026-08-30 12:00:05', 0, 105),
(12, 'save10', 'coupon', 104, '2026-08-30 12:00:05', 0, 109),
(13, 'Tee', 'line_item', 901, '2026-10-05 14:00:05', 0, 118),
(14, 'Mug', 'line_item', 106, '2026-09-05 16:00:05', 0, 131),
(15, 'Mug', 'line_item', 107, '2026-09-08 13:00:05', 0, 142),
(16, 'Tee', 'line_item', 108, '2026-09-10 11:00:05', 0, 154),
(17, 'Mug', 'line_item', 109, '2026-09-12 14:50:05', 0, 166),
(18, 'Sticker', 'line_item', 109, '2026-09-12 14:50:05', 0, 175),
(19, 'Gift wrap', 'fee', 109, '2026-09-12 14:50:05', 0, 184),
(20, 'Loyalty discount', 'fee', 109, '2026-09-12 14:50:05', 0, 189),
(21, 'Flat rate', 'shipping', 109, '2026-09-12 14:50:05', 0, 194),
(18, 'Sticker', 'line_item', 109, '2026-09-12 14:55:05', 1, 198),
(22, 'Tee', 'line_item', 110, '2026-09-15 16:00:05', 0, 214),
(23, 'Flat rate', 'shipping', 110, '2026-09-15 16:00:05', 0, 223),
(24, 'Mug', 'line_item', 111, '2026-09-20 10:00:05', 0, 230),
(25, 'Flat rate', 'shipping', 111, '2026-09-20 10:00:05', 0, 239),
(26, 'Mug', 'line_item', 902, '2026-09-22 12:00:05', 0, 245),
(27, 'Flat rate', 'shipping', 902, '2026-09-22 12:00:05', 0, 255),
(28, 'Tee', 'line_item', 112, '2026-10-01 13:00:05', 0, 264),
(29, 'Sticker', 'line_item', 113, '2026-10-03 14:00:05', 0, 280),
(30, 'Flat rate', 'shipping', 113, '2026-10-03 14:00:05', 0, 289),
(31, 'Mug', 'line_item', 114, '2026-10-04 10:00:05', 0, 297),
(32, 'Mug', 'line_item', 115, '2026-10-07 10:00:05', 0, 309),
(33, 'Mug', 'line_item', 116, '2026-10-08 10:00:05', 0, 320),
(33, 'Mug', 'line_item', 116, '2026-10-08 13:00:05', 1, 332),
(34, 'Mug', 'line_item', 117, '2026-10-09 10:00:05', 0, 346),
(35, 'Flat rate', 'shipping', 117, '2026-10-09 10:00:05', 0, 355),
(36, 'Mug', 'line_item', 904, '2026-09-10 10:00:05', 0, 362),
(37, 'Mug', 'line_item', 118, '2026-09-28 14:00:05', 0, 495),
(38, 'Mug', 'line_item', 119, '2026-09-30 14:00:05', 0, 504);

INSERT INTO {db:Identifier}.wp_woocommerce_order_itemmeta
    (meta_id, order_item_id, meta_key, meta_value, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 1, '_product_id', '11', '2026-08-10 14:00:05', 0, 13),
(2, 1, '_variation_id', '0', '2026-08-10 14:00:05', 0, 14),
(3, 1, '_qty', '1', '2026-08-10 14:00:05', 0, 15),
(4, 1, '_tax_class', '', '2026-08-10 14:00:05', 0, 16),
(5, 1, '_line_subtotal', '20', '2026-08-10 14:00:05', 0, 17),
(6, 1, '_line_subtotal_tax', '2', '2026-08-10 14:00:05', 0, 18),
(7, 1, '_line_total', '20', '2026-08-10 14:00:05', 0, 19),
(8, 1, '_line_tax', '2', '2026-08-10 14:00:05', 0, 20),
(9, 2, '_product_id', '12', '2026-08-10 14:00:05', 0, 22),
(10, 2, '_variation_id', '121', '2026-08-10 14:00:05', 0, 23),
(11, 2, '_qty', '1', '2026-08-10 14:00:05', 0, 24),
(12, 2, '_tax_class', '', '2026-08-10 14:00:05', 0, 25),
(13, 2, '_line_subtotal', '30', '2026-08-10 14:00:05', 0, 26),
(14, 2, '_line_subtotal_tax', '3', '2026-08-10 14:00:05', 0, 27),
(15, 2, '_line_total', '30', '2026-08-10 14:00:05', 0, 28),
(16, 2, '_line_tax', '3', '2026-08-10 14:00:05', 0, 29),
(17, 3, 'method_id', 'flat_rate', '2026-08-10 14:00:05', 0, 31),
(18, 3, 'cost', '10', '2026-08-10 14:00:05', 0, 32),
(19, 3, 'total_tax', '1', '2026-08-10 14:00:05', 0, 33),
(20, 4, 'rate_id', '1', '2026-08-10 14:00:05', 0, 35),
(21, 4, 'label', 'Tax', '2026-08-10 14:00:05', 0, 36),
(22, 4, 'tax_amount', '5', '2026-08-10 14:00:05', 0, 37),
(23, 4, 'shipping_tax_amount', '1', '2026-08-10 14:00:05', 0, 38),
(3, 1, '_qty', '2', '2026-08-10 14:03:05', 0, 39),
(5, 1, '_line_subtotal', '40', '2026-08-10 14:03:05', 0, 40),
(7, 1, '_line_total', '40', '2026-08-10 14:03:05', 0, 41),
(6, 1, '_line_subtotal_tax', '4', '2026-08-10 14:03:05', 0, 42),
(8, 1, '_line_tax', '4', '2026-08-10 14:03:05', 0, 43),
(20, 4, 'rate_id', '1', '2026-08-10 14:03:05', 1, 45),
(21, 4, 'label', 'Tax', '2026-08-10 14:03:05', 1, 46),
(22, 4, 'tax_amount', '5', '2026-08-10 14:03:05', 1, 47),
(23, 4, 'shipping_tax_amount', '1', '2026-08-10 14:03:05', 1, 48),
(24, 5, 'rate_id', '1', '2026-08-10 14:03:05', 0, 50),
(25, 5, 'label', 'Tax', '2026-08-10 14:03:05', 0, 51),
(26, 5, 'tax_amount', '7', '2026-08-10 14:03:05', 0, 52),
(27, 5, 'shipping_tax_amount', '1', '2026-08-10 14:03:05', 0, 53),
(28, 6, '_product_id', '13', '2026-08-20 15:00:05', 0, 62),
(29, 6, '_variation_id', '0', '2026-08-20 15:00:05', 0, 63),
(30, 6, '_qty', '3', '2026-08-20 15:00:05', 0, 64),
(31, 6, '_tax_class', '', '2026-08-20 15:00:05', 0, 65),
(32, 6, '_line_subtotal', '15', '2026-08-20 15:00:05', 0, 66),
(33, 6, '_line_subtotal_tax', '1.5', '2026-08-20 15:00:05', 0, 67),
(34, 6, '_line_total', '15', '2026-08-20 15:00:05', 0, 68),
(35, 6, '_line_tax', '1.5', '2026-08-20 15:00:05', 0, 69),
(36, 7, 'rate_id', '1', '2026-08-20 15:00:05', 0, 71),
(37, 7, 'label', 'Tax', '2026-08-20 15:00:05', 0, 72),
(38, 7, 'tax_amount', '1.5', '2026-08-20 15:00:05', 0, 73),
(39, 7, 'shipping_tax_amount', '0', '2026-08-20 15:00:05', 0, 74),
(40, 8, '_product_id', '14', '2026-09-01 02:00:05', 0, 79),
(41, 8, '_variation_id', '0', '2026-09-01 02:00:05', 0, 80),
(42, 8, '_qty', '1', '2026-09-01 02:00:05', 0, 81),
(43, 8, '_tax_class', '', '2026-09-01 02:00:05', 0, 82),
(44, 8, '_line_subtotal', '25', '2026-09-01 02:00:05', 0, 83),
(45, 8, '_line_subtotal_tax', '2.5', '2026-09-01 02:00:05', 0, 84),
(46, 8, '_line_total', '25', '2026-09-01 02:00:05', 0, 85),
(47, 8, '_line_tax', '2.5', '2026-09-01 02:00:05', 0, 86),
(48, 9, 'method_id', 'flat_rate', '2026-09-01 02:00:05', 0, 88),
(49, 9, 'cost', '5', '2026-09-01 02:00:05', 0, 89),
(50, 9, 'total_tax', '0.5', '2026-09-01 02:00:05', 0, 90),
(51, 10, '_product_id', '12', '2026-08-30 12:00:05', 0, 97),
(52, 10, '_variation_id', '122', '2026-08-30 12:00:05', 0, 98),
(53, 10, '_qty', '2', '2026-08-30 12:00:05', 0, 99),
(54, 10, '_tax_class', '', '2026-08-30 12:00:05', 0, 100),
(55, 10, '_line_subtotal', '60', '2026-08-30 12:00:05', 0, 101),
(56, 10, '_line_subtotal_tax', '6', '2026-08-30 12:00:05', 0, 102),
(57, 10, '_line_total', '54', '2026-08-30 12:00:05', 0, 103),
(58, 10, '_line_tax', '5.4', '2026-08-30 12:00:05', 0, 104),
(59, 11, 'method_id', 'flat_rate', '2026-08-30 12:00:05', 0, 106),
(60, 11, 'cost', '10', '2026-08-30 12:00:05', 0, 107),
(61, 11, 'total_tax', '1', '2026-08-30 12:00:05', 0, 108),
(62, 12, 'discount_amount', '6', '2026-08-30 12:00:05', 0, 110),
(63, 12, 'discount_amount_tax', '0.6', '2026-08-30 12:00:05', 0, 111),
(64, 13, '_product_id', '12', '2026-10-05 14:00:05', 0, 119),
(65, 13, '_variation_id', '122', '2026-10-05 14:00:05', 0, 120),
(66, 13, '_qty', '-1', '2026-10-05 14:00:05', 0, 121),
(67, 13, '_tax_class', '', '2026-10-05 14:00:05', 0, 122),
(68, 13, '_line_subtotal', '-27', '2026-10-05 14:00:05', 0, 123),
(69, 13, '_line_subtotal_tax', '-2.7', '2026-10-05 14:00:05', 0, 124),
(70, 13, '_line_total', '-27', '2026-10-05 14:00:05', 0, 125),
(71, 13, '_line_tax', '-2.7', '2026-10-05 14:00:05', 0, 126),
(72, 13, '_refunded_item_id', '10', '2026-10-05 14:00:05', 0, 127),
(73, 14, '_product_id', '11', '2026-09-05 16:00:05', 0, 132),
(74, 14, '_variation_id', '0', '2026-09-05 16:00:05', 0, 133),
(75, 14, '_qty', '1', '2026-09-05 16:00:05', 0, 134),
(76, 14, '_tax_class', '', '2026-09-05 16:00:05', 0, 135),
(77, 14, '_line_subtotal', '20', '2026-09-05 16:00:05', 0, 136),
(78, 14, '_line_subtotal_tax', '2', '2026-09-05 16:00:05', 0, 137),
(79, 14, '_line_total', '20', '2026-09-05 16:00:05', 0, 138),
(80, 14, '_line_tax', '2', '2026-09-05 16:00:05', 0, 139),
(81, 15, '_product_id', '11', '2026-09-08 13:00:05', 0, 143),
(82, 15, '_variation_id', '0', '2026-09-08 13:00:05', 0, 144),
(83, 15, '_qty', '2', '2026-09-08 13:00:05', 0, 145),
(84, 15, '_tax_class', '', '2026-09-08 13:00:05', 0, 146),
(85, 15, '_line_subtotal', '40', '2026-09-08 13:00:05', 0, 147),
(86, 15, '_line_subtotal_tax', '4', '2026-09-08 13:00:05', 0, 148),
(87, 15, '_line_total', '40', '2026-09-08 13:00:05', 0, 149),
(88, 15, '_line_tax', '4', '2026-09-08 13:00:05', 0, 150),
(89, 16, '_product_id', '12', '2026-09-10 11:00:05', 0, 155),
(90, 16, '_variation_id', '121', '2026-09-10 11:00:05', 0, 156),
(91, 16, '_qty', '1', '2026-09-10 11:00:05', 0, 157),
(92, 16, '_tax_class', '', '2026-09-10 11:00:05', 0, 158),
(93, 16, '_line_subtotal', '30', '2026-09-10 11:00:05', 0, 159),
(94, 16, '_line_subtotal_tax', '3', '2026-09-10 11:00:05', 0, 160),
(95, 16, '_line_total', '30', '2026-09-10 11:00:05', 0, 161),
(96, 16, '_line_tax', '3', '2026-09-10 11:00:05', 0, 162),
(97, 17, '_product_id', '11', '2026-09-12 14:50:05', 0, 167),
(98, 17, '_variation_id', '0', '2026-09-12 14:50:05', 0, 168),
(99, 17, '_qty', '1', '2026-09-12 14:50:05', 0, 169),
(100, 17, '_tax_class', '', '2026-09-12 14:50:05', 0, 170),
(101, 17, '_line_subtotal', '20', '2026-09-12 14:50:05', 0, 171),
(102, 17, '_line_subtotal_tax', '2', '2026-09-12 14:50:05', 0, 172),
(103, 17, '_line_total', '20', '2026-09-12 14:50:05', 0, 173),
(104, 17, '_line_tax', '2', '2026-09-12 14:50:05', 0, 174),
(105, 18, '_product_id', '13', '2026-09-12 14:50:05', 0, 176),
(106, 18, '_variation_id', '0', '2026-09-12 14:50:05', 0, 177),
(107, 18, '_qty', '1', '2026-09-12 14:50:05', 0, 178),
(108, 18, '_tax_class', '', '2026-09-12 14:50:05', 0, 179),
(109, 18, '_line_subtotal', '5', '2026-09-12 14:50:05', 0, 180),
(110, 18, '_line_subtotal_tax', '0.5', '2026-09-12 14:50:05', 0, 181),
(111, 18, '_line_total', '5', '2026-09-12 14:50:05', 0, 182),
(112, 18, '_line_tax', '0.5', '2026-09-12 14:50:05', 0, 183),
(113, 19, '_fee_amount', '5', '2026-09-12 14:50:05', 0, 185),
(114, 19, '_line_total', '5', '2026-09-12 14:50:05', 0, 186),
(115, 19, '_line_tax', '0.5', '2026-09-12 14:50:05', 0, 187),
(116, 19, '_tax_status', 'taxable', '2026-09-12 14:50:05', 0, 188),
(117, 20, '_fee_amount', '-7', '2026-09-12 14:50:05', 0, 190),
(118, 20, '_line_total', '-7', '2026-09-12 14:50:05', 0, 191),
(119, 20, '_line_tax', '-0.7', '2026-09-12 14:50:05', 0, 192),
(120, 20, '_tax_status', 'taxable', '2026-09-12 14:50:05', 0, 193),
(121, 21, 'method_id', 'flat_rate', '2026-09-12 14:50:05', 0, 195),
(122, 21, 'cost', '10', '2026-09-12 14:50:05', 0, 196),
(123, 21, 'total_tax', '1', '2026-09-12 14:50:05', 0, 197),
(105, 18, '_product_id', '13', '2026-09-12 14:55:05', 1, 199),
(106, 18, '_variation_id', '0', '2026-09-12 14:55:05', 1, 200),
(107, 18, '_qty', '1', '2026-09-12 14:55:05', 1, 201),
(108, 18, '_tax_class', '', '2026-09-12 14:55:05', 1, 202),
(109, 18, '_line_subtotal', '5', '2026-09-12 14:55:05', 1, 203),
(110, 18, '_line_subtotal_tax', '0.5', '2026-09-12 14:55:05', 1, 204),
(111, 18, '_line_total', '5', '2026-09-12 14:55:05', 1, 205),
(112, 18, '_line_tax', '0.5', '2026-09-12 14:55:05', 1, 206),
(124, 22, '_product_id', '12', '2026-09-15 16:00:05', 0, 215),
(125, 22, '_variation_id', '121', '2026-09-15 16:00:05', 0, 216),
(126, 22, '_qty', '1', '2026-09-15 16:00:05', 0, 217),
(127, 22, '_tax_class', '', '2026-09-15 16:00:05', 0, 218),
(128, 22, '_line_subtotal', '31.818182', '2026-09-15 16:00:05', 0, 219),
(129, 22, '_line_subtotal_tax', '3.18', '2026-09-15 16:00:05', 0, 220),
(130, 22, '_line_total', '31.818182', '2026-09-15 16:00:05', 0, 221),
(131, 22, '_line_tax', '3.18', '2026-09-15 16:00:05', 0, 222),
(132, 23, 'method_id', 'flat_rate', '2026-09-15 16:00:05', 0, 224),
(133, 23, 'cost', '10', '2026-09-15 16:00:05', 0, 225),
(134, 23, 'total_tax', '1', '2026-09-15 16:00:05', 0, 226),
(135, 24, '_product_id', '11', '2026-09-20 10:00:05', 0, 231),
(136, 24, '_variation_id', '0', '2026-09-20 10:00:05', 0, 232),
(137, 24, '_qty', '1', '2026-09-20 10:00:05', 0, 233),
(138, 24, '_tax_class', '', '2026-09-20 10:00:05', 0, 234),
(139, 24, '_line_subtotal', '20', '2026-09-20 10:00:05', 0, 235),
(140, 24, '_line_subtotal_tax', '2', '2026-09-20 10:00:05', 0, 236),
(141, 24, '_line_total', '20', '2026-09-20 10:00:05', 0, 237),
(142, 24, '_line_tax', '2', '2026-09-20 10:00:05', 0, 238),
(143, 25, 'method_id', 'flat_rate', '2026-09-20 10:00:05', 0, 240),
(144, 25, 'cost', '10', '2026-09-20 10:00:05', 0, 241),
(145, 25, 'total_tax', '1', '2026-09-20 10:00:05', 0, 242),
(146, 26, '_product_id', '11', '2026-09-22 12:00:05', 0, 246),
(147, 26, '_variation_id', '0', '2026-09-22 12:00:05', 0, 247),
(148, 26, '_qty', '-1', '2026-09-22 12:00:05', 0, 248),
(149, 26, '_tax_class', '', '2026-09-22 12:00:05', 0, 249),
(150, 26, '_line_subtotal', '-20', '2026-09-22 12:00:05', 0, 250),
(151, 26, '_line_subtotal_tax', '-2', '2026-09-22 12:00:05', 0, 251),
(152, 26, '_line_total', '-20', '2026-09-22 12:00:05', 0, 252),
(153, 26, '_line_tax', '-2', '2026-09-22 12:00:05', 0, 253),
(154, 26, '_refunded_item_id', '24', '2026-09-22 12:00:05', 0, 254),
(155, 27, 'method_id', 'flat_rate', '2026-09-22 12:00:05', 0, 256),
(156, 27, 'cost', '-10', '2026-09-22 12:00:05', 0, 257),
(157, 27, 'total_tax', '-1', '2026-09-22 12:00:05', 0, 258),
(158, 27, '_refunded_item_id', '25', '2026-09-22 12:00:05', 0, 259),
(159, 28, '_product_id', '12', '2026-10-01 13:00:05', 0, 265),
(160, 28, '_variation_id', '121', '2026-10-01 13:00:05', 0, 266),
(161, 28, '_qty', '2', '2026-10-01 13:00:05', 0, 267),
(162, 28, '_tax_class', '', '2026-10-01 13:00:05', 0, 268),
(163, 28, '_line_subtotal', '60', '2026-10-01 13:00:05', 0, 269),
(164, 28, '_line_subtotal_tax', '6', '2026-10-01 13:00:05', 0, 270),
(165, 28, '_line_total', '60', '2026-10-01 13:00:05', 0, 271),
(166, 28, '_line_tax', '6', '2026-10-01 13:00:05', 0, 272),
(167, 29, '_product_id', '13', '2026-10-03 14:00:05', 0, 281),
(168, 29, '_variation_id', '0', '2026-10-03 14:00:05', 0, 282),
(169, 29, '_qty', '2', '2026-10-03 14:00:05', 0, 283),
(170, 29, '_tax_class', '', '2026-10-03 14:00:05', 0, 284),
(171, 29, '_line_subtotal', '10', '2026-10-03 14:00:05', 0, 285),
(172, 29, '_line_subtotal_tax', '1', '2026-10-03 14:00:05', 0, 286),
(173, 29, '_line_total', '10', '2026-10-03 14:00:05', 0, 287),
(174, 29, '_line_tax', '1', '2026-10-03 14:00:05', 0, 288),
(175, 30, 'method_id', 'flat_rate', '2026-10-03 14:00:05', 0, 290),
(176, 30, 'cost', '5', '2026-10-03 14:00:05', 0, 291),
(177, 30, 'total_tax', '0.5', '2026-10-03 14:00:05', 0, 292),
(178, 31, '_product_id', '11', '2026-10-04 10:00:05', 0, 298),
(179, 31, '_variation_id', '0', '2026-10-04 10:00:05', 0, 299),
(180, 31, '_qty', '1', '2026-10-04 10:00:05', 0, 300),
(181, 31, '_tax_class', '', '2026-10-04 10:00:05', 0, 301),
(182, 31, '_line_subtotal', '20', '2026-10-04 10:00:05', 0, 302),
(183, 31, '_line_subtotal_tax', '2', '2026-10-04 10:00:05', 0, 303),
(184, 31, '_line_total', '20', '2026-10-04 10:00:05', 0, 304),
(185, 31, '_line_tax', '2', '2026-10-04 10:00:05', 0, 305),
(186, 32, '_product_id', '11', '2026-10-07 10:00:05', 0, 310),
(187, 32, '_variation_id', '0', '2026-10-07 10:00:05', 0, 311),
(188, 32, '_qty', '1', '2026-10-07 10:00:05', 0, 312),
(189, 32, '_tax_class', '', '2026-10-07 10:00:05', 0, 313),
(190, 32, '_line_subtotal', '20', '2026-10-07 10:00:05', 0, 314),
(191, 32, '_line_subtotal_tax', '2', '2026-10-07 10:00:05', 0, 315),
(192, 32, '_line_total', '20', '2026-10-07 10:00:05', 0, 316),
(193, 32, '_line_tax', '2', '2026-10-07 10:00:05', 0, 317),
(194, 33, '_product_id', '11', '2026-10-08 10:00:05', 0, 321),
(195, 33, '_variation_id', '0', '2026-10-08 10:00:05', 0, 322),
(196, 33, '_qty', '1', '2026-10-08 10:00:05', 0, 323),
(197, 33, '_tax_class', '', '2026-10-08 10:00:05', 0, 324),
(198, 33, '_line_subtotal', '20', '2026-10-08 10:00:05', 0, 325),
(199, 33, '_line_subtotal_tax', '2', '2026-10-08 10:00:05', 0, 326),
(200, 33, '_line_total', '20', '2026-10-08 10:00:05', 0, 327),
(201, 33, '_line_tax', '2', '2026-10-08 10:00:05', 0, 328),
(194, 33, '_product_id', '11', '2026-10-08 13:00:05', 1, 333),
(195, 33, '_variation_id', '0', '2026-10-08 13:00:05', 1, 334),
(196, 33, '_qty', '1', '2026-10-08 13:00:05', 1, 335),
(197, 33, '_tax_class', '', '2026-10-08 13:00:05', 1, 336),
(198, 33, '_line_subtotal', '20', '2026-10-08 13:00:05', 1, 337),
(199, 33, '_line_subtotal_tax', '2', '2026-10-08 13:00:05', 1, 338),
(200, 33, '_line_total', '20', '2026-10-08 13:00:05', 1, 339),
(201, 33, '_line_tax', '2', '2026-10-08 13:00:05', 1, 340),
(202, 34, '_product_id', '11', '2026-10-09 10:00:05', 0, 347),
(203, 34, '_variation_id', '0', '2026-10-09 10:00:05', 0, 348),
(204, 34, '_qty', '2', '2026-10-09 10:00:05', 0, 349),
(205, 34, '_tax_class', '', '2026-10-09 10:00:05', 0, 350),
(206, 34, '_line_subtotal', '45', '2026-10-09 10:00:05', 0, 351),
(207, 34, '_line_subtotal_tax', '4.5', '2026-10-09 10:00:05', 0, 352),
(208, 34, '_line_total', '45', '2026-10-09 10:00:05', 0, 353),
(209, 34, '_line_tax', '4.5', '2026-10-09 10:00:05', 0, 354),
(210, 35, 'method_id', 'flat_rate', '2026-10-09 10:00:05', 0, 356),
(211, 35, 'cost', '9', '2026-10-09 10:00:05', 0, 357),
(212, 35, 'total_tax', '0.9', '2026-10-09 10:00:05', 0, 358),
(213, 36, '_product_id', '11', '2026-09-10 10:00:05', 0, 363),
(214, 36, '_variation_id', '0', '2026-09-10 10:00:05', 0, 364),
(215, 36, '_qty', '-1', '2026-09-10 10:00:05', 0, 365),
(216, 36, '_tax_class', '', '2026-09-10 10:00:05', 0, 366),
(217, 36, '_line_subtotal', '-20', '2026-09-10 10:00:05', 0, 367),
(218, 36, '_line_subtotal_tax', '-2', '2026-09-10 10:00:05', 0, 368),
(219, 36, '_line_total', '-20', '2026-09-10 10:00:05', 0, 369),
(220, 36, '_line_tax', '-2', '2026-09-10 10:00:05', 0, 370),
(221, 36, '_refunded_item_id', '15', '2026-09-10 10:00:05', 0, 371),
(222, 37, '_product_id', '11', '2026-09-28 14:00:05', 0, 496),
(223, 37, '_variation_id', '0', '2026-09-28 14:00:05', 0, 497),
(224, 37, '_qty', '1', '2026-09-28 14:00:05', 0, 498),
(225, 37, '_tax_class', '', '2026-09-28 14:00:05', 0, 499),
(226, 37, '_line_subtotal', '20', '2026-09-28 14:00:05', 0, 500),
(227, 37, '_line_subtotal_tax', '2', '2026-09-28 14:00:05', 0, 501),
(228, 37, '_line_total', '20', '2026-09-28 14:00:05', 0, 502),
(229, 37, '_line_tax', '2', '2026-09-28 14:00:05', 0, 503),
(230, 38, '_product_id', '11', '2026-09-30 14:00:05', 0, 505),
(231, 38, '_variation_id', '0', '2026-09-30 14:00:05', 0, 506),
(232, 38, '_qty', '1', '2026-09-30 14:00:05', 0, 507),
(233, 38, '_tax_class', '', '2026-09-30 14:00:05', 0, 508),
(234, 38, '_line_subtotal', '20', '2026-09-30 14:00:05', 0, 509),
(235, 38, '_line_subtotal_tax', '2', '2026-09-30 14:00:05', 0, 510),
(236, 38, '_line_total', '20', '2026-09-30 14:00:05', 0, 511),
(237, 38, '_line_tax', '2', '2026-09-30 14:00:05', 0, 512);

INSERT INTO {db:Identifier}.wp_wc_product_meta_lookup
    (product_id, sku, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(11, 'MUG', '2026-08-01 00:00:05', 0, 1),
(12, 'TEE', '2026-08-01 00:00:05', 0, 2),
(121, 'TEE-M', '2026-08-01 00:00:05', 0, 3),
(122, 'TEE-L', '2026-08-01 00:00:05', 0, 4),
(13, '', '2026-08-01 00:00:05', 0, 5),
(14, 'CAP', '2026-08-01 00:00:05', 0, 6),
(14, 'CAP', '2026-10-10 10:00:05', 1, 359);

-- Products, their categories and brands. Categories (product_cat) and
-- brands (product_brand) are the owner's, now: a line counts in its
-- product's latest terms, whatever they were when it sold. Categories and
-- brands are on the product, not on its variations (121, 122): WooCommerce
-- puts only shipping class and visibility terms on a variation, and its
-- lines name the product (12).
--   11  Mug       Kitchen, Gifts and Kitchen > Accessories; no brand
--   12  Tee       T-Shirts (under Clothing); two brands, Acme and Northwind,
--                 a third, Beta, put on and then deleted
--   13  Sticker   renamed Sticker pack; Uncategorized, moved there from
--                 Gifts; Acme; moved to the trash on October 20, after its
--                 sale: its terms stay
--   14  Cap       Clothing, Northwind; deleted on October 10, after its sale
--   15  Tote      Gifts and Clothing > Accessories, Acme; never sold
--   16  Apron     Kitchen; a draft, never sold
--   17  Notebook  Gifts; in the trash, never sold
-- Kitchen was renamed Kitchen & Dining. A product is linked to the term's
-- term_taxonomy_id, here term_id + 10, so a join on term_id finds nothing.
-- T-Shirts was at the top until September 10, then moved under Clothing:
-- its parent is Clothing's term_id, 16, which no term_taxonomy_id has.
-- Two categories are named Accessories, one under Clothing (term 24), one
-- under Kitchen (term 25, whose number is also Uncategorized's
-- term_taxonomy_id): WordPress refuses a name twice under one parent
-- only. The Mug is in Kitchen and in the Accessories under it.
-- Two terms are named Uncategorized: 1 in the posts' category, 15 in
-- product_cat. Each product also has its product_type term (simple,
-- variable), which is no category. Posts other than products are there as
-- the CDC copy holds them: a page and the placeholders HPOS keeps for
-- orders, with the orders' ids.

INSERT INTO {db:Identifier}.wp_posts
    (ID, post_title, post_status, post_type, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(2, 'Sample Page', 'publish', 'page', '2026-08-01 00:00:05', 0, 401),
(11, 'Mug', 'publish', 'product', '2026-08-01 00:00:05', 0, 402),
(12, 'Tee', 'publish', 'product', '2026-08-01 00:00:05', 0, 403),
(121, 'Tee - M', 'publish', 'product_variation', '2026-08-01 00:00:05', 0, 404),
(122, 'Tee - L', 'publish', 'product_variation', '2026-08-01 00:00:05', 0, 405),
(13, 'Sticker', 'publish', 'product', '2026-08-01 00:00:05', 0, 406),
(14, 'Cap', 'publish', 'product', '2026-08-01 00:00:05', 0, 407),
(15, 'Tote', 'publish', 'product', '2026-08-15 10:00:05', 0, 408),
(16, 'Apron', 'draft', 'product', '2026-09-01 10:00:05', 0, 409),
(17, 'Notebook', 'publish', 'product', '2026-09-01 10:00:05', 0, 410),
(101, 'Order', 'draft', 'shop_order_placehold', '2026-08-10 14:00:05', 0, 411),
(112, 'Order', 'draft', 'shop_order_placehold', '2026-10-01 13:00:05', 0, 412),
(13, 'Sticker pack', 'publish', 'product', '2026-09-20 10:00:05', 0, 413),
(17, 'Notebook', 'trash', 'product', '2026-09-25 10:00:05', 0, 414),
(14, 'Cap', 'publish', 'product', '2026-10-10 10:00:05', 1, 415),
(13, 'Sticker pack', 'trash', 'product', '2026-10-20 10:00:05', 0, 416);

INSERT INTO {db:Identifier}.wp_terms
    (term_id, name, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 'Uncategorized', '2026-08-01 00:00:05', 0, 421),
(2, 'simple', '2026-08-01 00:00:05', 0, 422),
(4, 'variable', '2026-08-01 00:00:05', 0, 423),
(15, 'Uncategorized', '2026-08-01 00:00:05', 0, 424),
(16, 'Clothing', '2026-08-01 00:00:05', 0, 425),
(17, 'T-Shirts', '2026-08-01 00:00:05', 0, 426),
(18, 'Kitchen', '2026-08-01 00:00:05', 0, 427),
(19, 'Gifts', '2026-08-01 00:00:05', 0, 428),
(20, 'Acme', '2026-08-01 00:00:05', 0, 429),
(21, 'Northwind', '2026-08-01 00:00:05', 0, 430),
(22, 'gift', '2026-08-01 00:00:05', 0, 431),
(23, 'Beta', '2026-09-05 10:00:05', 0, 432),
(18, 'Kitchen & Dining', '2026-09-15 10:00:05', 0, 433),
(23, 'Beta', '2026-09-06 10:00:05', 1, 434),
(24, 'Accessories', '2026-09-10 10:00:05', 0, 435),
(25, 'Accessories', '2026-09-10 10:00:05', 0, 436);

INSERT INTO {db:Identifier}.wp_term_taxonomy
    (term_taxonomy_id, term_id, taxonomy, parent, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(1, 1, 'category', 0, '2026-08-01 00:00:05', 0, 441),
(2, 2, 'product_type', 0, '2026-08-01 00:00:05', 0, 442),
(4, 4, 'product_type', 0, '2026-08-01 00:00:05', 0, 443),
(25, 15, 'product_cat', 0, '2026-08-01 00:00:05', 0, 444),
(26, 16, 'product_cat', 0, '2026-08-01 00:00:05', 0, 445),
(27, 17, 'product_cat', 0, '2026-08-01 00:00:05', 0, 446),
(28, 18, 'product_cat', 0, '2026-08-01 00:00:05', 0, 447),
(29, 19, 'product_cat', 0, '2026-08-01 00:00:05', 0, 448),
(30, 20, 'product_brand', 0, '2026-08-01 00:00:05', 0, 449),
(31, 21, 'product_brand', 0, '2026-08-01 00:00:05', 0, 450),
(32, 22, 'product_tag', 0, '2026-08-01 00:00:05', 0, 451),
(33, 23, 'product_brand', 0, '2026-09-05 10:00:05', 0, 452),
(33, 23, 'product_brand', 0, '2026-09-06 10:00:05', 1, 453),
(27, 17, 'product_cat', 16, '2026-09-10 10:00:05', 0, 454),
(34, 24, 'product_cat', 16, '2026-09-10 10:00:05', 0, 455),
(35, 25, 'product_cat', 18, '2026-09-10 10:00:05', 0, 456);

INSERT INTO {db:Identifier}.wp_term_relationships
    (object_id, term_taxonomy_id, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version) SETTINGS session_timezone = 'UTC' VALUES
(11, 2, '2026-08-01 00:00:05', 0, 461),
(11, 28, '2026-08-01 00:00:05', 0, 462),
(11, 29, '2026-08-01 00:00:05', 0, 463),
(11, 32, '2026-08-01 00:00:05', 0, 464),
(12, 4, '2026-08-01 00:00:05', 0, 465),
(12, 27, '2026-08-01 00:00:05', 0, 466),
(12, 30, '2026-08-01 00:00:05', 0, 467),
(12, 31, '2026-08-01 00:00:05', 0, 468),
(13, 2, '2026-08-01 00:00:05', 0, 469),
(13, 29, '2026-08-01 00:00:05', 0, 470),
(13, 30, '2026-08-01 00:00:05', 0, 471),
(14, 2, '2026-08-01 00:00:05', 0, 472),
(14, 26, '2026-08-01 00:00:05', 0, 473),
(14, 31, '2026-08-01 00:00:05', 0, 474),
(15, 2, '2026-08-15 10:00:05', 0, 475),
(15, 29, '2026-08-15 10:00:05', 0, 476),
(15, 30, '2026-08-15 10:00:05', 0, 477),
(16, 2, '2026-09-01 10:00:05', 0, 478),
(16, 28, '2026-09-01 10:00:05', 0, 479),
(17, 2, '2026-09-01 10:00:05', 0, 480),
(17, 29, '2026-09-01 10:00:05', 0, 481),
(12, 33, '2026-09-05 10:00:05', 0, 482),
(12, 33, '2026-09-06 10:00:05', 1, 483),
(13, 29, '2026-09-20 10:00:05', 1, 484),
(13, 25, '2026-09-20 10:00:05', 0, 485),
(14, 2, '2026-10-10 10:00:05', 1, 486),
(14, 26, '2026-10-10 10:00:05', 1, 487),
(14, 31, '2026-10-10 10:00:05', 1, 488),
(15, 34, '2026-09-10 10:00:05', 0, 489),
(11, 35, '2026-09-10 10:00:05', 0, 490);
