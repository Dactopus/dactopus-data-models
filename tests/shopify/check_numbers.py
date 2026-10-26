"""Ask the commerce model questions over tests/shopify/fixture.sql and compare
the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the
fixture into one database (the query parameter db) and building the Shopify
package over it in the shop's time zone, America/New_York:

    clickhouse client --param_db=shopify_input --multiquery < sources/shopify/input.sql
    clickhouse client --param_db=shopify_input --multiquery < tests/shopify/fixture.sql
    dbt build --project-dir sources/shopify --profiles-dir tests \
        --vars '{shopify_input_database: shopify_input, shopify_timezone: America/New_York}'
    OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York python3 tests/shopify/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus. The model is asked in the
zone it was built in, $OSSIE_CLICKHOUSE_TIME_ZONE.

Orders in the fixture, test order 1009 left out (sales, refunded):
    August     1001 (110), 1002 (80, guest), 1003 (30, 22:00 on August 31
               in New York, September 1 in UTC)
    September  1004 (181, refunded 45 on October 3), 1005 (60, cancelled and
               refunded 60), 1006 (210, refunded 210 at 22:00 on September
               30 in New York, October 1 in UTC), 1007 (137), 1008 (169.50,
               processed September 12, created October 2), 1010 (70,
               guest, cancelled unpaid on October 2)
    October    1011 (40, free shipping), 1012 (272.50, guest, import duties
               34.20 and their tax 4.45 inside)
1001 also sold a 25 gift card, refunded on August 20, and 1007 took a 12
tip: both are inside the order's total_price and neither is a sale. Cancelled: 1005 and 1010. Customer 1 by processed_at: 1001, 1004, 1008,
1007. Customer 2: 1003, 1005 (cancelled), 1006, 1011. The input also holds
1004's version before its refund, placed for customer 2, 1005's version between its cancel and
refund with the same updated_at but an earlier load, and second copies of
1011 and 1006's refund, and a later version of 1004's refund with the same
line; the numbers are those of the latest versions only.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check  # noqa: E402

MODEL = "entities/commerce.yaml"

CASES = [
    # revenue: every order as placed = 110 + 80 + 30 + 181 + 60 + 210 + 137
    # + 169.50 + 70 + 40 + 272.50 = 1360 over 11 orders, 1012's duties
    # inside, as in Shopify's total sales (the test order's 500 is not
    # there; with 1001's gift card and 1007's tip it would be 1397).
    # refunded_amount: 45 + 60 + 210 = 315, without 1001's refunded gift
    # card, which Shopify's reports do not count as a return (340 with it).
    # net_revenue leaves out cancelled 1005 and 1010 and subtracts the
    # rest's refunds: 1360 - 60 - 70 - 45 - 210 = 975 (950 with the gift
    # card); revenue - refunded_amount would be 1045, the gap is 1010,
    # cancelled with nothing refunded. refund_rate = refunded_amount /
    # revenue.
    # average_order_value = goods after discounts over orders, as Shopify's
    # reports define it: subtotal 1360 - 76.95 shipping - 62.85 tax - 34.20
    # duties = 1186 over 11 orders, cancelled included. Discounts are the lines', as
    # Shopify's Discounts are ("product discount + the product's
    # proportional share of a cart-wide discount", https://help.shopify.com/
    # en/manual/reports-and-analytics/shopify-reports/report-types/
    # default-reports/finances-report), without tax: 29 (1004) + 15 (1008,
    # 16.95 with tax); 1011's free shipping is not there. Shipping after its discounts and without tax: 10 + 10 +
    # 10 + 5 + 15 (1008's 16.95 less 1.95 tax) + 10 + 0 (1011) + 16.95
    # (1012) = 76.95. Tax 12 (1007) + 17.55 + 1.95 (1008) + 31.35 (1012's
    # lines, shipping and duties) = 62.85. Customers 1 and 2; guests do not
    # count.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "orders.refunded_amount",
      "-m", "sales_events.net_revenue", "-m", "orders.refund_rate",
      "-m", "orders.average_order_value", "-m", "orders.discount_amount",
      "-m", "orders.shipping_amount", "-m", "orders.tax_amount", "-m", "orders.customers"],
     [{"orders.order_count": 11, "orders.revenue": 1360, "orders.refunded_amount": 315,
       "sales_events.net_revenue": 975, "orders.refund_rate": 315 / 1360,
       "orders.average_order_value": 1186 / 11, "orders.discount_amount": 44,
       "orders.shipping_amount": 76.95, "orders.tax_amount": 62.85, "orders.customers": 2}]),
    # By month of processed_at in New York. 1003 is August (September in
    # UTC); 1008 is September (created in October). September net:
    # (181 - 45) + (210 - 210) + 137 + 169.50 = 442.50. August net: 110
    # (1001, its gift card refund not a return) + 80 + 30. Refunds by order
    # month: 1004, 1005 and 1006 are September's, 1004's refund in October
    # included; 1001's gift card is not there. October: 1011 40 + 1012
    # 272.50.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "sales_events.net_revenue",
      "-m", "orders.refunded_amount", "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "orders.order_count": 3, "orders.revenue": 220,
       "sales_events.net_revenue": 220, "orders.refunded_amount": 0},
      {"order_month": "2026-09-01", "orders.order_count": 6, "orders.revenue": 827.5,
       "sales_events.net_revenue": 442.5, "orders.refunded_amount": 315},
      {"order_month": "2026-10-01", "orders.order_count": 2, "orders.revenue": 312.5,
       "sales_events.net_revenue": 312.5, "orders.refunded_amount": 0}]),
    # Revenue without cancelled orders: 1360 - 60 - 70.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-f", "orders.is_cancelled = false"],
     [{"orders.order_count": 9, "orders.revenue": 1230}]),
    # Placed before midnight of September 1, a time without an offset, which
    # is read in the zone the model is served in, New York: August's 1001,
    # 1002 and 1003 (22:00 on August 31), 110 + 80 + 30. Served in UTC, 1003
    # (02:00 on September 1 there) is not there: 2 orders, 190. A plain
    # string reads as the TIMESTAMP literal does.
    (["-m", "orders.order_count", "-m", "orders.revenue",
      "-f", "orders.order_time < TIMESTAMP '2026-09-01 00:00:00'"],
     [{"orders.order_count": 3, "orders.revenue": 220}]),
    (["-m", "orders.order_count", "-m", "orders.revenue",
      "-f", "orders.order_time < '2026-09-01 00:00:00'"],
     [{"orders.order_count": 3, "orders.revenue": 220}]),
    # Refunds by the month they were made, in New York: 1001's gift card in
    # August, a refund of 0 as it is not a return (25 paid back), 1005's 60
    # and 1006's 210 (September 30, October 1 in UTC) in September, 1004's
    # 45 and 1010's cancel, a refund of no money, in October; the test
    # order's 500 is not there. In UTC September and October would be 60
    # and 255.
    (["-m", "refund_count", "-m", "refunds_total", "-d", "refunds.refund_month",
      "-o", "refunds.refund_month"],
     [{"refund_month": "2026-08-01", "refund_count": 1, "refunds_total": 0},
      {"refund_month": "2026-09-01", "refund_count": 2, "refunds_total": 270},
      {"refund_month": "2026-10-01", "refund_count": 2, "refunds_total": 45}]),
    # The same refunds by the month of their order, through the order: 1001's
    # gift card in August; 1004's 45, 1005's 60, 1006's 210 and 1010's 0 in
    # September, as orders.refunded_amount by order month. October's 1011
    # and 1012 have none.
    (["-m", "refund_count", "-m", "refunds_total", "-d", "orders.order_month",
      "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "refund_count": 1, "refunds_total": 0},
      {"order_month": "2026-09-01", "refund_count": 4, "refunds_total": 315}]),
    # Sales by the month they happened, as Shopify's reports count them:
    # each order in its month, each refund and cancel in its own. August
    # 1001 110 + 1002 80 + 1003 30 (1001's gift card refund is 0) = 220.
    # September 1004 181 + 1005 60 + 1006 210 + 1007 137 + 1008 169.50 +
    # 1010 70, less 1005's refund 60 and 1006's 210 (September 30 in New
    # York) = 557.50. October 1011 40 + 1012 272.50, less 1004's refund 45
    # and 1010's cancel 70 = 197.50. 975 in all, as net_revenue by the
    # month of the order above (220, 442.50, 312.50). 1005, cancelled and
    # refunded whole at once, has no cancel to take back: counting its
    # cancel as well would take 60 more off September.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_month",
      "-o", "sales_events.event_month"],
     [{"event_month": "2026-08-01", "sales_events.net_revenue": 220},
      {"event_month": "2026-09-01", "sales_events.net_revenue": 557.5},
      {"event_month": "2026-10-01", "sales_events.net_revenue": 197.5}]),
    # The same sales by kind of event: the 11 orders, 1360; refunds 45 +
    # 60 + 210 = 315 (the gift card's and 1010's cancel are 0); 1010's
    # cancel takes back its 70.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_type",
      "-o", "sales_events.event_type"],
     [{"event_type": "cancellation", "sales_events.net_revenue": -70},
      {"event_type": "order", "sales_events.net_revenue": 1360},
      {"event_type": "refund", "sales_events.net_revenue": -315}]),
    # Units per order over the 11 orders: the lines' 18 items (see
    # items_sold below) / 11. Gift cards and tips are not goods: 1001's
    # gift card and 1007's tip would make it 20 / 11.
    (["-m", "orders.items_per_order"],
     [{"orders.items_per_order": 18 / 11}]),
    # By shipping city, as typed: New York 1001 (2 items, 110), 1004 (3,
    # 181), 1007 (2, 137); San Francisco 1010 (1, 70, cancelled); Toronto
    # 1005 (1, 60, cancelled), 1006 (1, 210), 1008 (2, 169.50), 1011 (2,
    # 40), 1012 (2, 272.50); no address 1002 (1, 80), 1003 (1, 30).
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "orders.items_per_order",
      "-d", "orders.shipping_city", "-o", "orders.shipping_city"],
     [{"shipping_city": "New York", "orders.order_count": 3, "orders.revenue": 428,
       "orders.items_per_order": 7 / 3},
      {"shipping_city": "San Francisco", "orders.order_count": 1, "orders.revenue": 70,
       "orders.items_per_order": 1.0},
      {"shipping_city": "Toronto", "orders.order_count": 5, "orders.revenue": 752,
       "orders.items_per_order": 1.6},
      {"shipping_city": None, "orders.order_count": 2, "orders.revenue": 110,
       "orders.items_per_order": 1.0}]),
    # US: 1001 110, 1004 181 (net 136), 1007 137, 1010 70 (cancelled).
    # CA: 1005 60 (cancelled), 1006 210 (net 0), 1008 169.50, 1011 40, 1012
    # 272.50.
    # No address: 1002 80, 1003 30.
    (["-m", "orders.revenue", "-m", "sales_events.net_revenue", "-d", "orders.shipping_country",
      "-o", "orders.shipping_country"],
     [{"shipping_country": "CA", "orders.revenue": 752, "sales_events.net_revenue": 482},
      {"shipping_country": "US", "orders.revenue": 498, "sales_events.net_revenue": 383},
      {"shipping_country": None, "orders.revenue": 110, "sales_events.net_revenue": 110}]),
    # Paid: 1007, 1008, 1011, 1012. PENDING (1002) is unpaid; 1010's voided authorization and 1003's
    # expired one are voided (unpaid 2, voided 1 if EXPIRED were unpaid). 1001
    # (its gift card) and 1004 are partially refunded. 1005 is refunded: its
    # earlier version, paid, has the same updated_at but an earlier load.
    # The mapping of every Shopify status is decided in #4.
    (["-m", "orders.order_count", "-d", "orders.financial_status", "-o", "orders.financial_status"],
     [{"financial_status": "paid", "orders.order_count": 4},
      {"financial_status": "partially_refunded", "orders.order_count": 2},
      {"financial_status": "refunded", "orders.order_count": 2},
      {"financial_status": "unpaid", "orders.order_count": 1},
      {"financial_status": "voided", "orders.order_count": 2}]),
    # Fulfilled: 1001; partially: 1007; ON_HOLD (1011) and the download
    # 1003, which Shopify leaves unfulfilled, are unfulfilled, as are the
    # rest: 1006, refunded whole before shipping, as FULFILLMENT_NOT_REQUIRED
    # (API 2026-10), and cancelled 1010 as UNFULFILLED (earlier versions).
    # The mapping of every Shopify status is decided in #4.
    (["-m", "orders.order_count", "-d", "orders.fulfillment_status",
      "-o", "orders.fulfillment_status"],
     [{"fulfillment_status": "fulfilled", "orders.order_count": 1},
      {"fulfillment_status": "partially_fulfilled", "orders.order_count": 1},
      {"fulfillment_status": "unfulfilled", "orders.order_count": 9}]),
    # The customer's orders in sequence of processed_at, cancelled ones
    # skipped: 1001 110 and 1003 30 are first; 1004 181 and 1006 210
    # second (1006 would be third if cancelled 1005 counted); 1008 169.50
    # and 1011 40 third; 1007 137 fourth. In sequence of created_at, 1007
    # would be third (187) and 1008 fourth (169.50). Guests and cancelled
    # orders have no number: 1002 80, 1005 60, 1010 70, 1012 272.50.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-d", "orders.customer_order_number",
      "-o", "orders.customer_order_number"],
     [{"customer_order_number": 1, "orders.order_count": 2, "orders.revenue": 140},
      {"customer_order_number": 2, "orders.order_count": 2, "orders.revenue": 391},
      {"customer_order_number": 3, "orders.order_count": 2, "orders.revenue": 209.5},
      {"customer_order_number": 4, "orders.order_count": 1, "orders.revenue": 137},
      {"customer_order_number": None, "orders.order_count": 4, "orders.revenue": 482.5}]),
    # New: 1001 110 + 1003 30. Repeat: 1004 181 (net 136), 1006 210 (net
    # 0), 1007 137, 1008 169.50, 1011 40. None: 1002 80, 1005 60, 1010 70,
    # 1012 272.50.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "sales_events.net_revenue",
      "-d", "orders.new_vs_repeat", "-o", "orders.new_vs_repeat"],
     [{"new_vs_repeat": "new", "orders.order_count": 2, "orders.revenue": 140,
       "sales_events.net_revenue": 140},
      {"new_vs_repeat": "repeat", "orders.order_count": 5, "orders.revenue": 737.5,
       "sales_events.net_revenue": 482.5},
      {"new_vs_repeat": None, "orders.order_count": 4, "orders.revenue": 482.5,
       "sales_events.net_revenue": 352.5}]),
    # Repeat orders over the orders that have a customer and are not
    # cancelled, the ones numbered in sequence: 5 / 7. Guests (1002, 1010,
    # 1012) and cancelled 1005 are not counted; over all orders it would be
    # 5 / 11.
    (["-m", "orders.repeat_order_share"],
     [{"orders.repeat_order_share": 5 / 7}]),
    # Lines of the 11 orders: 18 items ordered, 14 left after refunds and
    # cancels (1004 -1, 1005 -1, 1006 -1, 1010 -1; 15 if 1005's earlier
    # version were read). line_revenue is after discounts and without tax:
    # 1008's lines are 90 and 45, not 101.70 and 50.85, and the total is
    # the orders' revenue less shipping, tax and duties, 1360 - 76.95 -
    # 62.85 - 34.20 = 1186 (1220.20 if 1012's duties were goods).
    # The gift card and the tip are not lines (20 items, 1223 with them);
    # 1003's download, a custom item without product, tax or shipping like
    # the tip, is (17 items and 1156 if it were dropped too).
    (["-m", "items_sold", "-m", "items_net", "-m", "line_revenue"],
     [{"items_sold": 18, "items_net": 14, "line_revenue": 1186}]),
    # Top SKU by items: TEE-M 2 (1001) + 2 (1004); the test order's 10
    # would make it 14.
    (["-m", "items_sold", "-d", "order_lines.sku", "-o", "items_sold desc", "-l", "1"],
     [{"sku": "TEE-M", "items_sold": 4}]),
    # Top SKU by revenue: JACKET 200 (1006, refunded: revenue as placed),
    # TEE-COTTON 190 (1012, without its duties) and TEE-M 100 + (100 - 10),
    # tied and ordered by SKU, HOODIE (100 - 19) + 100.
    (["-m", "line_revenue", "-d", "order_lines.sku", "-o", "line_revenue desc",
      "-o", "order_lines.sku", "-l", "4"],
     [{"sku": "JACKET", "line_revenue": 200},
      {"sku": "TEE-COTTON", "line_revenue": 190},
      {"sku": "TEE-M", "line_revenue": 190},
      {"sku": "HOODIE", "line_revenue": 181}]),
    # Products. Lines as in line_revenue above, each in its product's latest
    # type and vendor; a product type has no subcategories, so every
    # category is direct. Returns are the refund lines' subtotal, by the
    # month of the order, and without tax, as line_revenue: where prices
    # include tax, the subtotal less its tax, as Shopify's returns count it
    # (113 with 13 tax returned 100 on the development store, #1015; the
    # package's unit test covers it, no refund here has tax inside).
    # Returned: 1004's T-shirt 45, 1005's Cap 60 (refund) and 1010's Cap 60
    # (cancel), 1006's Jacket 200: 4 items, 365; net 1186 - 365 = 821.
    (["-m", "items_returned", "-m", "line_returned_amount", "-m", "line_net_revenue"],
     [{"items_returned": 4, "line_returned_amount": 365, "line_net_revenue": 821}]),
    # By category (product_type): Apparel 101 T-shirt 100 + 90, 104 Hoodie
    # 81 + 100, 106 Jacket 200, 108 Socks 40, 110 Cotton T-shirt 190 = 801
    # over 11 items, 1 T-shirt (45) and the Jacket (200) returned: 2 items,
    # 245, net 556. Kitchen 102 Mug 80 + 45 = 125, 2 items. None: 105 Cap
    # 60 + 60 (both returned), 107 Blanket 90 (deleted), 1003's Field guide
    # 30 and 1007's Gift wrap 20 (no product) = 260 over 5 items, 2
    # returned for 120. 801 + 125 + 260 = 1186, as line_revenue: a product
    # has one type. Read with 101's earlier type, Tops would have 190.
    (["-m", "category_items_sold", "-m", "category_revenue", "-m", "category_items_returned",
      "-m", "category_returned_amount", "-m", "category_net_revenue",
      "-d", "line_categories.category_path", "-f", "line_categories.is_direct = true",
      "-o", "line_categories.category_path"],
     [{"category_path": "Apparel", "category_items_sold": 11, "category_revenue": 801,
       "category_items_returned": 2, "category_returned_amount": 245, "category_net_revenue": 556},
      {"category_path": "Kitchen", "category_items_sold": 2, "category_revenue": 125,
       "category_items_returned": 0, "category_returned_amount": 0, "category_net_revenue": 125},
      {"category_path": None, "category_items_sold": 5, "category_revenue": 260,
       "category_items_returned": 2, "category_returned_amount": 120, "category_net_revenue": 140}]),
    # September by category: Apparel 90 + 81 + 200 + 100 = 471 (5 items),
    # Kitchen 45, none 60 + 60 + 20 + 90 = 230; 746, September's orders less
    # shipping, tax and the tip.
    (["-m", "category_revenue", "-m", "category_items_sold", "-d", "line_categories.category_path",
      "-f", "orders.order_month = DATE '2026-09-01'", "-o", "line_categories.category_path"],
     [{"category_path": "Apparel", "category_revenue": 471, "category_items_sold": 5},
      {"category_path": "Kitchen", "category_revenue": 45, "category_items_sold": 1},
      {"category_path": None, "category_revenue": 230, "category_items_sold": 4}]),
    # By brand (vendor): Acme 101 190, 105 120, 108 40, 110 190 = 540 over
    # 10 items, 3 returned for 165; Northwind 104 181, 106 200 = 381 over 3,
    # 1 returned for 200; dactopus-dev, the store's own name, 102 125 over 2;
    # none 107 90, 30, 20 = 140 over 3. Were the Hoodie's version of
    # September 1 read (same updated_at, earlier load), Acme would have 721
    # and Northwind 200.
    (["-m", "brand_items_sold", "-m", "brand_revenue", "-m", "brand_items_returned",
      "-m", "brand_returned_amount", "-m", "brand_net_revenue", "-d", "line_brands.brand",
      "-o", "line_brands.brand"],
     [{"brand": "Acme", "brand_items_sold": 10, "brand_revenue": 540, "brand_items_returned": 3,
       "brand_returned_amount": 165, "brand_net_revenue": 375},
      {"brand": "Northwind", "brand_items_sold": 3, "brand_revenue": 381, "brand_items_returned": 1,
       "brand_returned_amount": 200, "brand_net_revenue": 181},
      {"brand": "dactopus-dev", "brand_items_sold": 2, "brand_revenue": 125,
       "brand_items_returned": 0, "brand_returned_amount": 0, "brand_net_revenue": 125},
      {"brand": None, "brand_items_sold": 3, "brand_revenue": 140, "brand_items_returned": 0,
       "brand_returned_amount": 0, "brand_net_revenue": 140}]),
    # Brand by month: Acme August 100, September 90 + 60 + 60 = 210,
    # October 40 + 190 = 230; Northwind September 381, October none;
    # dactopus-dev August 80, September 45; none August 30, September 110.
    (["-m", "brand_revenue", "-d", "line_brands.brand", "-d", "orders.order_month",
      "-o", "line_brands.brand", "-o", "orders.order_month"],
     [{"brand": "Acme", "order_month": "2026-08-01", "brand_revenue": 100},
      {"brand": "Acme", "order_month": "2026-09-01", "brand_revenue": 210},
      {"brand": "Acme", "order_month": "2026-10-01", "brand_revenue": 230},
      {"brand": "Northwind", "order_month": "2026-09-01", "brand_revenue": 381},
      {"brand": "dactopus-dev", "order_month": "2026-08-01", "brand_revenue": 80},
      {"brand": "dactopus-dev", "order_month": "2026-09-01", "brand_revenue": 45},
      {"brand": None, "order_month": "2026-08-01", "brand_revenue": 30},
      {"brand": None, "order_month": "2026-09-01", "brand_revenue": 110}]),
    # Average order value of the orders with an Apparel line, each order
    # once, all of its goods: 1001 100, 1004 171 (a Hoodie and two
    # T-shirts), 1006 200, 1007 120 (the Gift wrap included), 1011 40, 1012
    # 190 = 821 over 6. Counting an order once per matching line would give
    # 992 over 7.
    (["-m", "orders.average_order_value", "-m", "orders.order_count",
      "-f", "line_categories.category_path = 'Apparel'"],
     [{"orders.average_order_value": 821 / 6, "orders.order_count": 6}]),
    # Catalog: 10 products; the Blanket (107) and the Lamp (113) are
    # deleted, the Blanket's old version delivered after its deletion
    # included, and the Gift Card (109) is no goods. Active (ACTIVE, and
    # UNLISTED, sold through a link) 8, draft 1 (111), archived 1 (the
    # Jacket, 106).
    (["-m", "products.product_count", "-d", "products.status", "-o", "products.status"],
     [{"status": "active", "products.product_count": 8},
      {"status": "archived", "products.product_count": 1},
      {"status": "draft", "products.product_count": 1}]),
    # Active by category: Apparel 5 (101, 103, 104, 108, 110), Home 1 (112,
    # unlisted), Kitchen 1 (102); the Cap (105) has no type and no row.
    (["-m", "product_categories.product_count", "-d", "product_categories.category_path",
      "-f", "products.status = 'active'", "-f", "product_categories.is_direct = true",
      "-o", "product_categories.category_path"],
     [{"category_path": "Apparel", "product_categories.product_count": 5},
      {"category_path": "Home", "product_categories.product_count": 1},
      {"category_path": "Kitchen", "product_categories.product_count": 1}]),
    # By brand: Acme 101, 103, 105, 108, 110; Northwind 104, 106;
    # dactopus-dev 102, 111, 112 (the Gift Card left out).
    (["-m", "product_brands.product_count", "-d", "product_brands.brand", "-o", "product_brands.brand"],
     [{"brand": "Acme", "product_brands.product_count": 5},
      {"brand": "Northwind", "product_brands.product_count": 2},
      {"brand": "dactopus-dev", "product_brands.product_count": 3}]),
    # Last sold, by the order's date, cancelled orders left out: 101
    # September 5 (the test order 1009 of September 20 left out too), 102
    # September 12, 104 September 15, 106 September 10 (refunded, not
    # cancelled), 108 October 2, 110 October 3. Never sold: 103, 111, 112,
    # and 105, sold only in the cancelled 1005 and 1010.
    (["-d", "products.product_id", "-d", "products.last_sold_date", "-o", "products.product_id"],
     [{"product_id": 101, "last_sold_date": "2026-09-05"},
      {"product_id": 102, "last_sold_date": "2026-09-12"},
      {"product_id": 103, "last_sold_date": None},
      {"product_id": 104, "last_sold_date": "2026-09-15"},
      {"product_id": 105, "last_sold_date": None},
      {"product_id": 106, "last_sold_date": "2026-09-10"},
      {"product_id": 108, "last_sold_date": "2026-10-02"},
      {"product_id": 110, "last_sold_date": "2026-10-03"},
      {"product_id": 111, "last_sold_date": None},
      {"product_id": 112, "last_sold_date": None}]),
    # Active products not sold since October 1: the T-shirt, Mug and Hoodie
    # last sold in September, and the Scarf, Cap and Poster never.
    (["-d", "products.title", "-f", "products.status = 'active'",
      "-f", "products.last_sold_date IS NULL OR products.last_sold_date < DATE '2026-10-01'",
      "-o", "products.title"],
     [{"title": "Cap"}, {"title": "Hoodie"}, {"title": "Mug"}, {"title": "Poster"},
      {"title": "Scarf"}, {"title": "T-shirt"}]),
]

if __name__ == "__main__":
    check(MODEL, CASES)
