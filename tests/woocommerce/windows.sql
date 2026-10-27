-- Hand-designed WooCommerce orders for the retention windows
-- (customers.second_order_within_N_days), loaded with fixture.sql into a
-- database of their own: check_numbers.py --windows asks about them there.
-- The windows need first orders from a year before the fixture's last sync.
-- The input database is the query parameter db, as in input.sql.
--
-- The orders are written once below and expanded into the input tables:
-- each is a mug, 20 and tax 2, a single change data capture version. A
-- completed order was paid five minutes after it was placed and completed
-- at its sync; a failed or pending one has neither date and is not counted.
-- 2010 is synced at 03:00 UTC on October 10: 23:00 on October 9 in New
-- York. The last sync of orders is then October 9 in the store's zone and
-- October 10 in UTC, so a clock read in UTC closes 2004's year. Customers,
-- first and second orders (placed at 11:00 in New York):
--   11     2001 September 1, 2025; 2002 August 1, 2026: 334 days
--   12     2003 October 8, 2025, alone: its year ended October 8, 2026
--   13     2004 October 9, 2025, alone: its year ends October 9, 2026
--   14     2005 May 1, 2026; 2007 July 30: 90 days, the day the 90-day
--          window ends. 2006, May 11, failed: neither.
--   15     2008 June 1, 2026; 2010 July 15: 44 days. 2009, June 6, still
--          pending: neither.
--   -2011  a guest by email: 2011 March 2, 2026; 2012 March 20, with the
--          email in other case and a space: 18 days

CREATE TABLE {db:Identifier}.window_orders
    (id UInt64, status String, customer_id UInt64, billing_email String, placed DateTime('UTC'), synced DateTime('UTC'))
ENGINE = Memory;

INSERT INTO {db:Identifier}.window_orders VALUES
(2001, 'wc-completed', 11, 'carol@example.com',         '2025-09-01 15:00:00', '2025-09-02 15:00:05'),
(2002, 'wc-completed', 11, 'carol@example.com',         '2026-08-01 15:00:00', '2026-08-02 15:00:05'),
(2003, 'wc-completed', 12, 'dan@example.com',           '2025-10-08 15:00:00', '2025-10-09 15:00:05'),
(2004, 'wc-completed', 13, 'erin@example.com',          '2025-10-09 15:00:00', '2025-10-10 15:00:05'),
(2005, 'wc-completed', 14, 'frank@example.com',         '2026-05-01 15:00:00', '2026-05-02 15:00:05'),
(2006, 'wc-failed',    14, 'frank@example.com',         '2026-05-11 15:00:00', '2026-05-11 15:00:05'),
(2007, 'wc-completed', 14, 'frank@example.com',         '2026-07-30 15:00:00', '2026-07-31 15:00:05'),
(2008, 'wc-completed', 15, 'grace@example.com',         '2026-06-01 15:00:00', '2026-06-02 15:00:05'),
(2009, 'wc-pending',   15, 'grace@example.com',         '2026-06-06 15:00:00', '2026-06-06 15:00:05'),
(2010, 'wc-completed', 15, 'grace@example.com',         '2026-07-15 15:00:00', '2026-10-10 03:00:00'),
(2011, 'wc-completed', 0,  'heidi@example.com',         '2026-03-02 15:00:00', '2026-03-03 15:00:05'),
(2012, 'wc-completed', 0,  ' Heidi@Example.com',        '2026-03-20 15:00:00', '2026-03-21 15:00:05');

INSERT INTO {db:Identifier}.wp_wc_orders
    (id, status, currency, type, tax_amount, total_amount, customer_id, billing_email, date_created_gmt, parent_order_id, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version)
SELECT id, status, 'USD', 'shop_order', 2, 22, customer_id, billing_email, placed, 0, synced, 0, id
FROM {db:Identifier}.window_orders;

INSERT INTO {db:Identifier}.wp_wc_order_operational_data
    (id, order_id, created_via, prices_include_tax, date_paid_gmt, date_completed_gmt, shipping_total_amount, shipping_tax_amount, discount_total_amount, discount_tax_amount, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version)
SELECT id, id, 'checkout', false,
       if(status = 'wc-completed', placed + 300, toDateTime(0, 'UTC')),
       if(status = 'wc-completed', synced - 5, toDateTime(0, 'UTC')),
       0, 0, 0, 0, synced, 0, id
FROM {db:Identifier}.window_orders;

INSERT INTO {db:Identifier}.wp_woocommerce_order_items
    (order_item_id, order_item_name, order_item_type, order_id, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version)
SELECT id, 'Mug', 'line_item', id, synced, 0, id
FROM {db:Identifier}.window_orders;

INSERT INTO {db:Identifier}.wp_woocommerce_order_itemmeta
    (meta_id, order_item_id, meta_key, meta_value, _peerdb_synced_at, _peerdb_is_deleted, _peerdb_version)
SELECT id * 10 + n, id, key, value, synced, 0, id * 10 + n
FROM {db:Identifier}.window_orders
ARRAY JOIN
    ['_product_id', '_variation_id', '_qty', '_tax_class', '_line_subtotal', '_line_subtotal_tax', '_line_total', '_line_tax'] AS key,
    ['11', '0', '1', '', '20', '2', '20', '2'] AS value,
    [1, 2, 3, 4, 5, 6, 7, 8] AS n;

DROP TABLE {db:Identifier}.window_orders;
