-- Hand-written Shopify rows for the retention windows
-- (customers.second_order_within_N_days), loaded with fixture.sql into a
-- database of their own: check_numbers.py --windows asks about them there.
-- The windows need first orders from a year before the fixture's last load.
-- The input database is the query parameter db, as in input.sql.
--
-- Each order is a Cap at 60, paid and shipped, loaded at midnight on
-- October 4 as the fixture's orders are, but 2009, whose last version comes
-- at 02:00 UTC on October 5: 22:00 on October 4 in New York. The last load
-- of orders is then October 4 in the shop's zone and October 5 in UTC, so a
-- clock read in UTC closes 2004's year. Customers, first and second orders
-- (11:00 in New York):
--   11  2001 September 1, 2025; 2002 August 1, 2026: 334 days
--   12  2003 October 3, 2025, alone: its year ended October 3, 2026
--   13  2004 October 4, 2025, alone: its year ends October 4, 2026
--   14  2005 May 1, 2026; 2007 July 30: 90 days, the day the 90-day
--       window ends. Test order 2006, May 11, is neither.
--   15  2008 June 1, 2026; 2009 July 15: 44 days

INSERT INTO {db:Identifier}.orders VALUES
-- (id, name, created_at, processed_at, updated_at, cancelled_at, closed_at, test,
--  customer_id, email, currency_code, presentment_currency_code,
--  display_financial_status, display_fulfillment_status, source_name, taxes_included,
--  total_price, shipping_price, shipping_tax, total_tax, total_refunded, current_total_price, total_tip,
--  total_duties, total_additional_fees, discount_codes, shipping_country_code, shipping_province_code, shipping_city, shipping_zip, loaded_at)
(2001, '#2001', '2025-09-01 15:00:00', '2025-09-01 15:00:00', '2025-09-02 15:00:00', NULL, '2025-09-02 15:00:00', false,
 11, 'carol@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2002, '#2002', '2026-08-01 15:00:00', '2026-08-01 15:00:00', '2026-08-02 15:00:00', NULL, '2026-08-02 15:00:00', false,
 11, 'carol@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2003, '#2003', '2025-10-03 15:00:00', '2025-10-03 15:00:00', '2025-10-04 15:00:00', NULL, '2025-10-04 15:00:00', false,
 12, 'dan@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2004, '#2004', '2025-10-04 15:00:00', '2025-10-04 15:00:00', '2025-10-05 15:00:00', NULL, '2025-10-05 15:00:00', false,
 13, 'erin@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2005, '#2005', '2026-05-01 15:00:00', '2026-05-01 15:00:00', '2026-05-02 15:00:00', NULL, '2026-05-02 15:00:00', false,
 14, 'frank@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2006, '#2006', '2026-05-11 15:00:00', '2026-05-11 15:00:00', '2026-05-12 15:00:00', NULL, '2026-05-12 15:00:00', true,
 14, 'frank@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2007, '#2007', '2026-07-30 15:00:00', '2026-07-30 15:00:00', '2026-07-31 15:00:00', NULL, '2026-07-31 15:00:00', false,
 14, 'frank@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2008, '#2008', '2026-06-01 15:00:00', '2026-06-01 15:00:00', '2026-06-02 15:00:00', NULL, '2026-06-02 15:00:00', false,
 15, 'grace@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00'),
(2009, '#2009', '2026-07-15 15:00:00', '2026-07-15 15:00:00', '2026-07-15 15:00:00', NULL, NULL, false,
 15, 'grace@example.com', 'USD', 'USD', 'PAID', 'UNFULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-04 00:00:00');

INSERT INTO {db:Identifier}.order_lines VALUES
-- (id, order_id, order_updated_at, product_id, variant_id, sku, title, variant_title, quantity, current_quantity,
--  original_unit_price, original_total, discount_allocated, total_tax, tax_rate, taxable, requires_shipping, is_gift_card, loaded_at)
(2011, 2001, '2025-09-02 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2021, 2002, '2026-08-02 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2031, 2003, '2025-10-04 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2041, 2004, '2025-10-05 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2051, 2005, '2026-05-02 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2061, 2006, '2026-05-12 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2071, 2007, '2026-07-31 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2081, 2008, '2026-06-02 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01'),
(2091, 2009, '2026-07-15 15:00:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-04 00:00:01');

-- 2009 shipped: its last version, loaded after the shop's midnight.
INSERT INTO {db:Identifier}.orders VALUES
(2009, '#2009', '2026-07-15 15:00:00', '2026-07-15 15:00:00', '2026-10-05 01:30:00', NULL, '2026-10-05 01:30:00', false,
 15, 'grace@example.com', 'USD', 'USD', 'PAID', 'FULFILLED', 'web', false,
 60, 0, 0, 0, 0, 60, 0, 0, 0, [], 'US', 'NY', 'New York', '10001', '2026-10-05 02:00:00');

INSERT INTO {db:Identifier}.order_lines VALUES
(2091, 2009, '2026-10-05 01:30:00', 105, 1051, 'CAP', 'Cap', NULL, 1, 1, 60, 60, 0, 0, 0, true, true, false, '2026-10-05 02:00:01');
