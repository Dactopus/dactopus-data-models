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

Orders in the fixture, test orders left out: 1009 (sales, refunded; customer
4's only order) and 1013 (customer 1's, after their last order):
    August     1001 (110), 1002 (80, guest), 1003 (30, 22:00 on August 31
               in New York, September 1 in UTC)
    September  1004 (181, refunded 45 on October 3), 1005 (60, cancelled and
               refunded 60), 1006 (210, refunded 210 at 22:00 on September
               30 in New York, October 1 in UTC), 1007 (137), 1008 (169.50,
               processed September 12, created October 2; its shipping
               16.95 refunded by an import on October 4 with processed_at
               September 20), 1010 (70, customer 3's only order, cancelled
               unpaid on October 2)
    October    1011 (40, free shipping), 1012 (272.50, guest, import duties
               34.20 and their tax 4.45 inside)
1001 also sold a 25 gift card, refunded on August 20, and 1007 took a 12
tip: both are inside the order's total_price and neither is a sale. Cancelled: 1005 and 1010. Customer 1 by processed_at: 1001, 1004, 1008,
1007. Customer 2: 1003, 1005 (cancelled), 1006, 1011. Customer 3: 1010
(cancelled). Guests: 1002, 1012. The input also holds
1004's version before its refund, placed for customer 2, 1008's version
before its shipping was refunded, 1005's version between its cancel and
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
    # refunded_amount: 45 + 60 + 210 + 16.95 (1008's shipping) = 331.95,
    # without 1001's refunded gift card, which Shopify's reports do not
    # count as a return (356.95 with it). net_revenue leaves out cancelled
    # 1005 and 1010 and subtracts the rest's refunds: 1360 - 60 - 70 - 45
    # - 210 - 16.95 = 958.05 (933.05 with the gift card); revenue -
    # refunded_amount would be 1028.05, the gap is 1010, cancelled with
    # nothing refunded. refund_rate = refunded_amount / revenue.
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
    # lines, shipping and duties) = 62.85. Customers 1, 2 and 3 (1010,
    # cancelled, is in the reports); guests do not count, nor customer 4,
    # whose only order is a test order.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "orders.refunded_amount",
      "-m", "sales_events.net_revenue", "-m", "orders.refund_rate",
      "-m", "orders.average_order_value", "-m", "orders.discount_amount",
      "-m", "orders.shipping_amount", "-m", "orders.tax_amount", "-m", "orders.buyer_count"],
     [{"orders.order_count": 11, "orders.revenue": 1360, "orders.refunded_amount": 331.95,
       "sales_events.net_revenue": 958.05, "orders.refund_rate": 331.95 / 1360,
       "orders.average_order_value": 1186 / 11, "orders.discount_amount": 44,
       "orders.shipping_amount": 76.95, "orders.tax_amount": 62.85, "orders.buyer_count": 3}]),
    # By month of processed_at in New York. 1003 is August (September in
    # UTC); 1008 is September (created in October). September net:
    # (181 - 45) + (210 - 210) + 137 + (169.50 - 16.95) = 425.55. August
    # net: 110 (1001, its gift card refund not a return) + 80 + 30.
    # Refunds by order month: 1004, 1005, 1006 and 1008 are September's,
    # 1004's refund in October included; 1001's gift card is not there.
    # October: 1011 40 + 1012 272.50.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "sales_events.net_revenue",
      "-m", "orders.refunded_amount", "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "orders.order_count": 3, "orders.revenue": 220,
       "sales_events.net_revenue": 220, "orders.refunded_amount": 0},
      {"order_month": "2026-09-01", "orders.order_count": 6, "orders.revenue": 827.5,
       "sales_events.net_revenue": 425.55, "orders.refunded_amount": 331.95},
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
    # August, a refund of 0 as it is not a return (25 paid back), 1005's
    # 60, 1006's 210 (September 30, October 1 in UTC) and 1008's 16.95
    # (processed September 20, created October 4) in September, 1004's 45
    # and 1010's cancel, a refund of no money, in October; the test order's
    # 500 is not there. In UTC September and October would be 76.95 and
    # 255. By created_at, 1008's refund would be October's: September 2,
    # 270, October 3, 61.95.
    (["-m", "refund_count", "-m", "refunds_total", "-d", "refunds.refund_month",
      "-o", "refunds.refund_month"],
     [{"refund_month": "2026-08-01", "refund_count": 1, "refunds_total": 0},
      {"refund_month": "2026-09-01", "refund_count": 3, "refunds_total": 286.95},
      {"refund_month": "2026-10-01", "refund_count": 2, "refunds_total": 45}]),
    # The same refunds by the month of their order, through the order: 1001's
    # gift card in August; 1004's 45, 1005's 60, 1006's 210, 1008's 16.95
    # and 1010's 0 in September, as orders.refunded_amount by order month.
    # October's 1011 and 1012 have none.
    (["-m", "refund_count", "-m", "refunds_total", "-d", "orders.order_month",
      "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "refund_count": 1, "refunds_total": 0},
      {"order_month": "2026-09-01", "refund_count": 5, "refunds_total": 331.95}]),
    # Sales by the month they happened, as Shopify's reports count them:
    # each order in its month, each refund and cancel in its own. August
    # 1001 110 + 1002 80 + 1003 30 (1001's gift card refund is 0) = 220.
    # September 1004 181 + 1005 60 + 1006 210 + 1007 137 + 1008 169.50 +
    # 1010 70, less 1005's refund 60, 1006's 210 (September 30 in New
    # York) and 1008's 16.95 (processed September 20) = 540.55; by
    # created_at 1008's refund would be October's, 557.50 and 180.55.
    # October 1011 40 + 1012 272.50, less 1004's refund 45 and 1010's
    # cancel 70 = 197.50. 958.05 in all, as net_revenue by the month of the
    # order above (220, 425.55, 312.50). 1005, cancelled and
    # refunded whole at once, has no cancel to take back: counting its
    # cancel as well would take 60 more off September.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_month",
      "-o", "sales_events.event_month"],
     [{"event_month": "2026-08-01", "sales_events.net_revenue": 220},
      {"event_month": "2026-09-01", "sales_events.net_revenue": 540.55},
      {"event_month": "2026-10-01", "sales_events.net_revenue": 197.5}]),
    # The same sales by kind of event: the 11 orders, 1360; refunds 45 +
    # 60 + 210 + 16.95 = 331.95 (the gift card's and 1010's cancel are 0);
    # 1010's cancel takes back its 70.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_type",
      "-o", "sales_events.event_type"],
     [{"event_type": "cancellation", "sales_events.net_revenue": -70},
      {"event_type": "order", "sales_events.net_revenue": 1360},
      {"event_type": "refund", "sales_events.net_revenue": -331.95}]),
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
    # CA: 1005 60 (cancelled), 1006 210 (net 0), 1008 169.50 (net 152.55),
    # 1011 40, 1012 272.50.
    # No address: 1002 80, 1003 30.
    (["-m", "orders.revenue", "-m", "sales_events.net_revenue", "-d", "orders.shipping_country",
      "-o", "orders.shipping_country"],
     [{"shipping_country": "CA", "orders.revenue": 752, "sales_events.net_revenue": 465.05},
      {"shipping_country": "US", "orders.revenue": 498, "sales_events.net_revenue": 383},
      {"shipping_country": None, "orders.revenue": 110, "sales_events.net_revenue": 110}]),
    # Paid: 1007, 1011, 1012. PENDING (1002) is unpaid; 1010's voided authorization and 1003's
    # expired one are voided (unpaid 2, voided 1 if EXPIRED were unpaid). 1001
    # (its gift card), 1004 and 1008 (its shipping) are partially refunded. 1005 is refunded: its
    # earlier version, paid, has the same updated_at but an earlier load.
    # The mapping of every Shopify status is decided in #4.
    (["-m", "orders.order_count", "-d", "orders.financial_status", "-o", "orders.financial_status"],
     [{"financial_status": "paid", "orders.order_count": 3},
      {"financial_status": "partially_refunded", "orders.order_count": 3},
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
    # The customer's orders in sequence of processed_at, as Shopify's
    # report of new and returning customers counts them: cancelled ones too
    # (#1012 on the development store, a customer's only order and
    # cancelled, is New, and #1021 after it Returning). First: 1001 110,
    # 1003 30 and 1010 70, customer 3's only order, cancelled. Second: 1004
    # 181 and cancelled 1005 60. Third: 1008 169.50 and 1006 210 (second
    # were cancelled 1005 skipped). Fourth: 1007 137 and 1011 40. In
    # sequence of created_at, 1007 would be third and 1008 fourth. Guests
    # (1002 80, 1012 272.50) have no number.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-d", "orders.customer_order_number",
      "-o", "orders.customer_order_number"],
     [{"customer_order_number": 1, "orders.order_count": 3, "orders.revenue": 210},
      {"customer_order_number": 2, "orders.order_count": 2, "orders.revenue": 241},
      {"customer_order_number": 3, "orders.order_count": 2, "orders.revenue": 379.5},
      {"customer_order_number": 4, "orders.order_count": 2, "orders.revenue": 177},
      {"customer_order_number": None, "orders.order_count": 2, "orders.revenue": 352.5}]),
    # New: 1001 110, 1003 30, 1010 70 (net 0, cancelled). Repeat: 1004 181
    # (net 136), 1005 60 (net 0, cancelled and refunded), 1006 210 (net 0),
    # 1007 137, 1008 169.50 (net 152.55), 1011 40. None: the guests, 1002 80
    # and 1012 272.50.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "sales_events.net_revenue",
      "-d", "orders.new_vs_repeat", "-o", "orders.new_vs_repeat"],
     [{"new_vs_repeat": "new", "orders.order_count": 3, "orders.revenue": 210,
       "sales_events.net_revenue": 140},
      {"new_vs_repeat": "repeat", "orders.order_count": 6, "orders.revenue": 797.5,
       "sales_events.net_revenue": 465.55},
      {"new_vs_repeat": None, "orders.order_count": 2, "orders.revenue": 352.5,
       "sales_events.net_revenue": 352.5}]),
    # Repeat orders over the orders that have a customer, the ones numbered
    # in sequence, cancelled ones included: 6 / 9. The guests (1002, 1012)
    # are not counted; over all orders it would be 6 / 11.
    (["-m", "orders.repeat_order_share"],
     [{"orders.repeat_order_share": 6 / 9}]),
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
      "-d", "line_categories.category_path", "-o", "line_categories.category_path"],
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
    # Lines by the product's status now, as in line_revenue above: active
    # 101 T-shirt 190, 102 Mug 125, 104 Hoodie 181, 105 Cap 120 (sold
    # only in cancelled orders, counted as the reports count them), 108
    # Socks 40, 110 Cotton T-shirt 190 = 846 over 14 items; archived 106
    # Jacket 200 over 1; empty 107 Blanket 90 (deleted), 1003's Field
    # guide 30 and 1007's Gift wrap 20 (no product) = 140 over 3. 1186 in
    # all, as line_revenue: no line is lost or counted twice.
    (["-m", "line_revenue", "-m", "items_sold", "-d", "products.status", "-o", "products.status"],
     [{"status": "active", "line_revenue": 846, "items_sold": 14},
      {"status": "archived", "line_revenue": 200, "items_sold": 1},
      {"status": None, "line_revenue": 140, "items_sold": 3}]),
    # Active by category: Apparel 5 (101, 103, 104, 108, 110), Home 1 (112,
    # unlisted), Kitchen 1 (102); the Cap (105) has no type and no row.
    (["-m", "product_categories.product_count", "-d", "product_categories.category_path",
      "-f", "products.status = 'active'", "-o", "product_categories.category_path"],
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
    # Customers are the ones Shopify's report of new and returning
    # customers counts: every order but test ones, cancelled ones included
    # (#1012 on the development store is New, and #1021 after it
    # Returning), in sequence of processed_at; dates and months are New
    # York's. Customers 1, 2 and 3; customer 4 has only a test order and no
    # row, and were cancelled orders left out, customer 3 would have none
    # either.
    #   1  first order 1001, August 10: cohort August. Last 1007, September
    #      15 (by created_at 1008, October 2; test order 1013, September 25,
    #      left out). 4 orders, net 110 + (181 - 45) + (169.50 - 16.95)
    #      + 137 = 535.55.
    #   2  first order 1003, 22:00 on August 31: cohort August (September in
    #      UTC). Last 1011, October 2. 4 orders, net 30 + 0 (1005, cancelled
    #      and refunded) + 0 (1006, refunded whole) + 40 = 70.
    #   3  first and last order 1010, September 25: cohort September. 1
    #      order, net 0.
    # The customers' net and the guests' 352.50 make 958.05, net_revenue.
    # By cohort: August 2 customers, 605.55, 302.775 each; September 1, 0.
    (["-m", "customers.customer_count", "-m", "customers.net_amount", "-m", "customers.average_customer_value",
      "-d", "customers.first_order_month", "-o", "customers.first_order_month"],
     [{"first_order_month": "2026-08-01", "customers.customer_count": 2, "customers.net_amount": 605.55,
       "customers.average_customer_value": 302.775},
      {"first_order_month": "2026-09-01", "customers.customer_count": 1, "customers.net_amount": 0,
       "customers.average_customer_value": 0}]),
    (["-m", "customers.net_amount", "-d", "customers.customer_id", "-d", "customers.first_order_date",
      "-d", "customers.last_order_date", "-d", "customers.number_of_orders", "-o", "customers.customer_id"],
     [{"customer_id": 1, "first_order_date": "2026-08-10", "last_order_date": "2026-09-15",
       "number_of_orders": 4, "customers.net_amount": 535.55},
      {"customer_id": 2, "first_order_date": "2026-08-31", "last_order_date": "2026-10-02",
       "number_of_orders": 4, "customers.net_amount": 70},
      {"customer_id": 3, "first_order_date": "2026-09-25", "last_order_date": "2026-09-25",
       "number_of_orders": 1, "customers.net_amount": 0}]),
    # Bought once: customer 3. Last order before September 20: customer 1.
    (["-m", "customers.customer_count", "-f", "customers.number_of_orders = 1"],
     [{"customers.customer_count": 1}]),
    (["-m", "customers.customer_count", "-f", "customers.last_order_date < '2026-09-20'"],
     [{"customers.customer_count": 1}]),
    # Buyers and customers: the same 3, every customer has an order the
    # reports count.
    (["-m", "orders.buyer_count", "-m", "customers.customer_count"],
     [{"orders.buyer_count": 3, "customers.customer_count": 3}]),
    # Days since the customer's previous order, between New York dates:
    # 1004 26 (August 10 to September 5), 1008 7, 1007 3; 1005 8 (August 31
    # to September 8; 7 between UTC dates), 1006 2 (from cancelled 1005; 10
    # from 1003), 1011 22; none on first orders. All repeat orders (26 + 7 +
    # 3 + 8 + 2 + 22) / 6 = 68 / 6; second orders 26 and 8, 17.
    (["-m", "orders.average_days_between_orders"],
     [{"orders.average_days_between_orders": 68 / 6}]),
    (["-m", "orders.average_days_between_orders", "-f", "orders.customer_order_number = 2"],
     [{"orders.average_days_between_orders": 17}]),
    # Months since the first order, as Shopify's months_since_first_purchase
    # (-1 on the first order, then calendar months between the orders'
    # months; on the development store a customer's orders of September 12
    # and October 5 are 1 apart): 1001, 1003, 1010 -1; 1004, 1008, 1007 1;
    # 1005 1, 1006 1, 1011 2. In UTC 1003 is September: 1005 and 1006 0,
    # 1011 1. The guests' orders have none and no buyer.
    (["-m", "orders.buyer_count", "-d", "orders.months_since_first_order", "-o", "orders.months_since_first_order"],
     [{"months_since_first_order": -1, "orders.buyer_count": 3},
      {"months_since_first_order": 1, "orders.buyer_count": 2},
      {"months_since_first_order": 2, "orders.buyer_count": 1},
      {"months_since_first_order": None, "orders.buyer_count": 0}]),
    # Buyers by cohort and month of order: August cohort August 2 (1001,
    # 1003), September 2, October 1 (1011); September cohort September 1.
    # The guests' orders (1002 in August, 1012 in October) have no cohort.
    (["-m", "orders.buyer_count", "-d", "customers.first_order_month", "-d", "orders.order_month",
      "-o", "customers.first_order_month", "-o", "orders.order_month"],
     [{"first_order_month": "2026-08-01", "order_month": "2026-08-01", "orders.buyer_count": 2},
      {"first_order_month": "2026-08-01", "order_month": "2026-09-01", "orders.buyer_count": 2},
      {"first_order_month": "2026-08-01", "order_month": "2026-10-01", "orders.buyer_count": 1},
      {"first_order_month": "2026-09-01", "order_month": "2026-09-01", "orders.buyer_count": 1},
      {"first_order_month": None, "order_month": "2026-08-01", "orders.buyer_count": 0},
      {"first_order_month": None, "order_month": "2026-10-01", "orders.buyer_count": 0}]),
]

# Second order within N days, for the retention windows the model does not
# have yet, counted where the window is over: its last day ended before the
# last load of orders, October 4 (06:00 in UTC, 02:00 in New York; 1008's
# refund came with it). Customer 1 took 26 days, customer 2 8 (to a
# cancelled order, as the report counts it), customer 3 has none. N = 30:
# customers 1 and 2 (first order before September 4), both yes, 2 of 2;
# customer 3's window ends October 25, empty. N = 60: no window is over.

if __name__ == "__main__":
    check(MODEL, CASES)
