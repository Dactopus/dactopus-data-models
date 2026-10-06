"""Ask the commerce model questions over tests/shopify/fixture.sql and compare
the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the
fixture into one database (the query parameter db) and building the Shopify
package over it in the shop's time zone, America/New_York:

    clickhouse client --param_db=shopify_input --multiquery < sources/shopify/input.sql
    clickhouse client --param_db=shopify_input --multiquery < tests/shopify/fixture.sql
    dbt build --project-dir sources/shopify --profiles-dir sources/shopify \
        --vars '{shopify_input_database: shopify_input, shopify_timezone: America/New_York}'
    python3 tests/shopify/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus.

Orders in the fixture, test order 1009 left out (sales, refunded):
    August     1001 (110), 1002 (80, guest), 1003 (30, 22:00 on August 31
               in New York, September 1 in UTC)
    September  1004 (181, refunded 45 on October 3), 1005 (60, cancelled and
               refunded 60), 1006 (210, refunded 210 at 22:00 on September
               30 in New York, October 1 in UTC), 1007 (137), 1008 (169.50,
               processed September 12, created October 2), 1010 (70,
               guest, cancelled unpaid)
    October    1011 (40, free shipping)
1001 also sold a 25 gift card, refunded on August 20, and 1007 took a 12
tip: both are inside the order's total_price and neither is a sale. Cancelled: 1005 and 1010. Customer 1 by processed_at: 1001, 1004, 1008,
1007. Customer 2: 1003, 1005 (cancelled), 1006, 1011. The input also holds
1004's version before its refund, 1005's version between its cancel and
refund with the same updated_at but an earlier load, and second copies of
1011 and 1006's refund; the numbers are those of the latest versions only.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check  # noqa: E402

MODEL = "entities/commerce.yaml"

CASES = [
    # revenue: every order as placed = 110 + 80 + 30 + 181 + 60 + 210 + 137
    # + 169.50 + 70 + 40 = 1087.50 over 10 orders (the test order's 500 is
    # not there; with 1001's gift card and 1007's tip it would be 1124.50).
    # refunded_amount: 45 + 60 + 210 = 315, without 1001's refunded gift
    # card, which Shopify's reports do not count as a return (340 with it).
    # net_revenue leaves out cancelled 1005 and 1010 and subtracts the
    # rest's refunds: 1087.50 - 60 - 70 - 45 - 210 = 702.50 (677.50 with
    # the gift card); revenue - refunded_amount would be 772.50, the gap is
    # 1010, cancelled with nothing refunded. refund_rate = refunded_amount
    # / revenue.
    # average_order_value = revenue / orders, cancelled included. Discounts are the lines', as
    # Shopify's Discounts are ("product discount + the product's
    # proportional share of a cart-wide discount", https://help.shopify.com/
    # en/manual/reports-and-analytics/shopify-reports/report-types/
    # default-reports/finances-report), without tax: 29 (1004) + 15 (1008,
    # 16.95 with tax); 1011's free shipping is not there. Shipping after its discounts and without tax: 10 + 10 +
    # 10 + 5 + 15 (1008's 16.95 less 1.95 tax) + 10 + 0 (1011). Tax 12
    # (1007) + 17.55 + 1.95 (1008). Customers 1 and 2; guests do not count.
    (["-m", "orders", "-m", "revenue", "-m", "refunded_amount", "-m", "net_revenue",
      "-m", "refund_rate", "-m", "average_order_value", "-m", "discount_total",
      "-m", "shipping_total", "-m", "tax_total", "-m", "customers"],
     [{"orders": 10, "revenue": 1087.5, "refunded_amount": 315, "net_revenue": 702.5,
       "refund_rate": 315 / 1087.5, "average_order_value": 108.75, "discount_total": 44,
       "shipping_total": 60, "tax_total": 31.5, "customers": 2}]),
    # By month of processed_at in New York. 1003 is August (September in
    # UTC); 1008 is September (created in October). September net:
    # (181 - 45) + (210 - 210) + 137 + 169.50 = 442.50. August net: 110
    # (1001, its gift card refund not a return) + 80 + 30. Refunds by order
    # month: 1004, 1005 and 1006 are September's, 1004's refund in October
    # included; 1001's gift card is not there.
    (["-m", "orders", "-m", "revenue", "-m", "net_revenue", "-m", "refunded_amount",
      "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "orders": 3, "revenue": 220, "net_revenue": 220, "refunded_amount": 0},
      {"order_month": "2026-09-01", "orders": 6, "revenue": 827.5, "net_revenue": 442.5, "refunded_amount": 315},
      {"order_month": "2026-10-01", "orders": 1, "revenue": 40, "net_revenue": 40, "refunded_amount": 0}]),
    # Revenue without cancelled orders: 1087.50 - 60 - 70.
    (["-m", "orders", "-m", "revenue", "-f", "orders.is_cancelled = false"],
     [{"orders": 8, "revenue": 957.5}]),
    # Refunds by the month they were made, in New York: 1001's gift card in
    # August, a refund of 0 as it is not a return (25 paid back), 1005's 60
    # and 1006's 210 (September 30, October 1 in UTC) in September, 1004's
    # 45 in October; the test order's 500 is not there. In UTC September
    # and October would be 60 and 255.
    (["-m", "refunds", "-m", "refunds_total", "-d", "refunds.refund_month", "-o", "refunds.refund_month"],
     [{"refund_month": "2026-08-01", "refunds": 1, "refunds_total": 0},
      {"refund_month": "2026-09-01", "refunds": 2, "refunds_total": 270},
      {"refund_month": "2026-10-01", "refunds": 1, "refunds_total": 45}]),
    # The same refunds by the month of their order, through the order: 1001's
    # gift card in August; 1004's 45, 1005's 60 and 1006's 210 in September,
    # as refunded_amount by order month. October's 1011 has none.
    (["-m", "refunds", "-m", "refunds_total", "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "refunds": 1, "refunds_total": 0},
      {"order_month": "2026-09-01", "refunds": 3, "refunds_total": 315}]),
    # US: 1001 110, 1004 181 (net 136), 1007 137, 1010 70 (cancelled).
    # CA: 1005 60 (cancelled), 1006 210 (net 0), 1008 169.50, 1011 40.
    # No address: 1002 80, 1003 30.
    (["-m", "revenue", "-m", "net_revenue", "-d", "orders.shipping_country", "-o", "orders.shipping_country"],
     [{"shipping_country": "CA", "revenue": 479.5, "net_revenue": 209.5},
      {"shipping_country": "US", "revenue": 498, "net_revenue": 383},
      {"shipping_country": None, "revenue": 110, "net_revenue": 110}]),
    # PENDING (1002) is unpaid; 1010's voided authorization and 1003's
    # expired one are voided (unpaid 2, voided 1 if EXPIRED were unpaid). 1001
    # (its gift card) and 1004 are partially refunded. 1005 is refunded: its
    # earlier version, paid, has the same updated_at but an earlier load.
    # The mapping of every Shopify status is decided in #4.
    (["-m", "orders", "-d", "orders.financial_status", "-o", "orders.financial_status"],
     [{"financial_status": "paid", "orders": 3}, {"financial_status": "partially_refunded", "orders": 2},
      {"financial_status": "refunded", "orders": 2}, {"financial_status": "unpaid", "orders": 1},
      {"financial_status": "voided", "orders": 2}]),
    # Fulfilled: 1001; partially: 1007; ON_HOLD (1011) and the download
    # 1003, which Shopify leaves unfulfilled, are unfulfilled. The mapping
    # of every Shopify status is decided in #4.
    (["-m", "orders", "-d", "orders.fulfillment_status", "-o", "orders.fulfillment_status"],
     [{"fulfillment_status": "fulfilled", "orders": 1}, {"fulfillment_status": "partially_fulfilled", "orders": 1},
      {"fulfillment_status": "unfulfilled", "orders": 8}]),
    # The customer's orders in sequence of processed_at, cancelled ones
    # skipped: 1001 110 and 1003 30 are first; 1004 181 and 1006 210
    # second (1006 would be third if cancelled 1005 counted); 1008 169.50
    # and 1011 40 third; 1007 137 fourth. In sequence of created_at, 1007
    # would be third (187) and 1008 fourth (169.50). Guests and cancelled
    # orders have no number: 1002 80, 1005 60, 1010 70.
    (["-m", "orders", "-m", "revenue", "-d", "orders.customer_order_number", "-o", "orders.customer_order_number"],
     [{"customer_order_number": 1, "orders": 2, "revenue": 140},
      {"customer_order_number": 2, "orders": 2, "revenue": 391},
      {"customer_order_number": 3, "orders": 2, "revenue": 209.5},
      {"customer_order_number": 4, "orders": 1, "revenue": 137},
      {"customer_order_number": None, "orders": 3, "revenue": 210}]),
    # New: 1001 110 + 1003 30. Repeat: 1004 181 (net 136), 1006 210 (net
    # 0), 1007 137, 1008 169.50, 1011 40. None: 1002 80, 1005 60, 1010 70.
    (["-m", "orders", "-m", "revenue", "-m", "net_revenue", "-d", "orders.new_vs_repeat", "-o", "orders.new_vs_repeat"],
     [{"new_vs_repeat": "new", "orders": 2, "revenue": 140, "net_revenue": 140},
      {"new_vs_repeat": "repeat", "orders": 5, "revenue": 737.5, "net_revenue": 482.5},
      {"new_vs_repeat": None, "orders": 3, "revenue": 210, "net_revenue": 80}]),
    # Repeat orders over the orders that have a customer and are not
    # cancelled, the ones numbered in sequence: 5 / 7. Guests (1002, 1010)
    # and cancelled 1005 are not counted; over all orders it would be 5 / 10.
    (["-m", "repeat_order_share"], [{"repeat_order_share": 5 / 7}]),
    # Lines of the 10 orders: 16 items ordered, 12 left after refunds and
    # cancels (1004 -1, 1005 -1, 1006 -1, 1010 -1; 13 if 1005's earlier
    # version were read). line_revenue is after discounts and without tax:
    # 1008's lines are 90 and 45, not 101.70 and 50.85, and the total is
    # the orders' revenue less shipping and tax, 1087.50 - 60 - 31.50 = 996.
    # The gift card and the tip are not lines (18 items, 1033 with them);
    # 1003's download, a custom item without product, tax or shipping like
    # the tip, is (15 items and 966 if it were dropped too).
    (["-m", "items_sold", "-m", "items_net", "-m", "line_revenue"],
     [{"items_sold": 16, "items_net": 12, "line_revenue": 996}]),
    # Top SKU by items: TEE-M 2 (1001) + 2 (1004); the test order's 10
    # would make it 14.
    (["-m", "items_sold", "-d", "order_lines.sku", "-o", "items_sold desc", "-l", "1"],
     [{"sku": "TEE-M", "items_sold": 4}]),
    # Top SKU by revenue: JACKET 200 (1006, refunded: revenue as placed),
    # TEE-M 100 + (100 - 10), HOODIE (100 - 19) + 100.
    (["-m", "line_revenue", "-d", "order_lines.sku", "-o", "line_revenue desc", "-l", "3"],
     [{"sku": "JACKET", "line_revenue": 200}, {"sku": "TEE-M", "line_revenue": 190},
      {"sku": "HOODIE", "line_revenue": 181}]),
]


if __name__ == "__main__":
    check(MODEL, CASES)
