"""Ask the commerce model questions over tests/woocommerce/fixture.sql and
compare the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the fixture
into one database (the query parameter db) and building the WooCommerce
package over it in the store's time zone, America/New_York:

    clickhouse client --param_db=woocommerce_input --multiquery < sources/woocommerce/input.sql
    clickhouse client --param_db=woocommerce_input --multiquery < tests/woocommerce/fixture.sql
    dbt build --project-dir sources/woocommerce --profiles-dir tests \
        --vars '{woocommerce_input_database: woocommerce_input, woocommerce_timezone: America/New_York, woocommerce_currency: USD}'
    OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York python3 tests/woocommerce/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus. The model is asked in the
zone it was built in, $OSSIE_CLICKHOUSE_TIME_ZONE.

The numbers are those of the store's reports with WooCommerce's default
settings: an order is dated by its payment and counted unless it is
pending, cancelled or failed; an order not yet paid is not counted. Orders
of the fixture (fixture.sql lists them):
    counted      101 (88), 103 (33), 104 (70.40, refunded 29.70), 109 (30.80),
                 110 (46), 111 (33, refunded 33), 112 (66, refunded 5),
                 113 (16.50), 117 (66 USD, 59.40 EUR): 9 orders, 449.70
    not counted  102 on hold (no payment date), 106 pending, 107 cancelled
                 (refund 904 of 22 on September 10 left out with it), 108
                 failed: rows of orders all the same
    not orders   114 in the trash, 115 a checkout draft, 116 deleted
By month of payment in New York: August 101, 103 (paid at 22:10 on August
31, September 1 in UTC); September 104 (placed August 30), 109, 110, 111;
October 112, 113 (paid on delivery October 6, placed October 3), 117.
Refunds of counted orders: 902 (111, 33) September 22, 903 (112, 5) October
2, 901 (104, 29.70) October 5.
Customer 1 by date placed: 101, 104, 109, 111, 117. Customer 2: 103, 107
(cancelled, not numbered), 110, 113.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check  # noqa: E402

MODEL = "entities/commerce.yaml"

CASES = [
    # revenue = the counted orders' totals: 88 + 33 + 70.40 + 30.80 + 46 +
    # 33 + 66 + 16.50 + 66 = 449.70 over 9 orders (565.20 over all 13 rows,
    # if pending 106, cancelled 107, failed 108 and on-hold 102 counted;
    # 114, 115 and 116 in it would make 631.20). 117 is 59.40 EUR at 0.9 EUR
    # per USD: 66 (59.40 if left in EUR). refunded_amount: 29.70 (104) + 33
    # (111) + 5 (112) = 67.70; net_revenue = 449.70 - 67.70 = 382, as
    # Analytics' total sales. average_order_value = goods after discounts
    # over orders, as Analytics' (and Shopify's) average order value: total
    # less shipping and tax, fees in: 70 + 25 + 54 + 18 (109: 20 + 5 - 7)
    # + 31.82 (110) + 20 + 60 + 10 + 50 = 338.82 over 9. Discounts: 104's
    # coupon, 6 without tax. Shipping without tax: 10 + 5 + 10 + 10 + 10 +
    # 10 + 0 + 5 + 10 (117's 9 EUR) = 70. Tax on goods and shipping: 8 + 3
    # + 6.40 + 2.80 + 4.18 + 3 + 6 + 1.50 + 6 = 40.88 (33.88 if tax_amount,
    # which leaves shipping tax out, were taken alone). Customers 1 and 2.
    (["-m", "orders", "-m", "revenue", "-m", "refunded_amount", "-m", "net_revenue",
      "-m", "refund_rate", "-m", "average_order_value", "-m", "discount_total",
      "-m", "shipping_total", "-m", "tax_total", "-m", "customers"],
     [{"orders": 9, "revenue": 449.7, "refunded_amount": 67.7, "net_revenue": 382,
       "refund_rate": 67.7 / 449.7, "average_order_value": 338.82 / 9, "discount_total": 6,
       "shipping_total": 70, "tax_total": 40.88, "customers": 2}]),
    # Every row of orders, counted or not: the 9 above and 102 (16.50), 106
    # (22), 107 (44), 108 (33): 13 orders, 565.20. Not 16: the trash, the
    # checkout draft and the deleted order are not orders.
    (["-m", "all_orders", "-m", "all_orders_total"],
     [{"all_orders": 13, "all_orders_total": 565.2}]),
    # Orders waiting for payment: 102 on hold (16.50) and 106 pending (22).
    # The counted metrics have none: orders would answer 0.
    (["-m", "all_orders", "-m", "all_orders_total", "-f", "orders.financial_status = 'unpaid'"],
     [{"all_orders": 2, "all_orders_total": 38.5}]),
    # Which rows the reports count.
    (["-m", "all_orders", "-d", "orders.in_sales_reports", "-o", "orders.in_sales_reports"],
     [{"in_sales_reports": False, "all_orders": 4}, {"in_sales_reports": True, "all_orders": 9}]),
    # By month of payment in New York. August: 101 88, 103 33 (September in
    # UTC). September: 104 70.40 (August by date placed), 109 30.80, 110 46,
    # 111 33; net 180.20 - 29.70 - 33 = 117.50, refunds by the month of their
    # order, 104's refund of October 5 included. October: 112 66, 113 16.50
    # (October 3 if dated when placed, and not counted in its earlier
    # version), 117 66; net 148.50 - 5.
    (["-m", "orders", "-m", "revenue", "-m", "net_revenue", "-m", "refunded_amount",
      "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "orders": 2, "revenue": 121, "net_revenue": 121, "refunded_amount": 0},
      {"order_month": "2026-09-01", "orders": 4, "revenue": 180.2, "net_revenue": 117.5, "refunded_amount": 62.7},
      {"order_month": "2026-10-01", "orders": 3, "revenue": 148.5, "net_revenue": 143.5, "refunded_amount": 5}]),
    # Paid before midnight of September 1, a time without an offset, which is
    # read in the zone the model is served in, New York: August's 101 88 and
    # 103 33 (22:10 on August 31). Served in UTC, 103 (02:10 on September 1
    # there) is not there: 1 order, 88. A plain string reads as the TIMESTAMP
    # literal does.
    (["-m", "orders", "-m", "revenue", "-f", "orders.order_time < TIMESTAMP '2026-09-01 00:00:00'"],
     [{"orders": 2, "revenue": 121}]),
    (["-m", "orders", "-m", "revenue", "-f", "orders.order_time < '2026-09-01 00:00:00'"],
     [{"orders": 2, "revenue": 121}]),
    # Sales by the month they happened, as the store's reports count them:
    # each order in the month of its payment, each refund in its own month.
    # August 101 88 + 103 33 = 121. September 104 70.40 + 109 30.80 + 110
    # 46 + 111 33 - refund 902 33 = 147.20. October 112 66 + 113 16.50 +
    # 117 66 - 903 5 - 901 29.70 = 113.80. 382 in all, as net_revenue by
    # the month of the order above (121, 117.50, 143.50), where 901 is
    # September's. Refund 904 of cancelled 107 would take 22 off September.
    (["-m", "net_revenue", "-d", "sales_events.event_month", "-o", "sales_events.event_month"],
     [{"event_month": "2026-08-01", "net_revenue": 121},
      {"event_month": "2026-09-01", "net_revenue": 147.2},
      {"event_month": "2026-10-01", "net_revenue": 113.8}]),
    # The same sales by kind of event: the 9 counted orders, 449.70, less
    # their refunds, 67.70. WooCommerce has no cancellation events: a
    # cancelled order is left out by its status.
    (["-m", "net_revenue", "-d", "sales_events.event_type", "-o", "sales_events.event_type"],
     [{"event_type": "order", "net_revenue": 449.7}, {"event_type": "refund", "net_revenue": -67.7}]),
    # Refunds by the month they were made: 902 (111, 33) on September 22;
    # 903 (112, 5, an amount without lines) on October 2 and 901 (104,
    # 29.70) on October 5. 904 (107, 22, September 10) is a refund of an
    # order the reports leave out, and they leave it out too: with it
    # September would be 2 refunds, 55.
    (["-m", "refunds", "-m", "refunds_total", "-d", "refunds.refund_month", "-o", "refunds.refund_month"],
     [{"refund_month": "2026-09-01", "refunds": 1, "refunds_total": 33},
      {"refund_month": "2026-10-01", "refunds": 2, "refunds_total": 34.7}]),
    # Payment state of every row. Paid: 101, 103, 109, 110, 113 (its
    # earlier version, processing without a payment date, would be unpaid),
    # 117. Partially refunded: 104, 112, and 107, paid before it was
    # cancelled and refunded in part after. Refunded: 111. Unpaid: 102 on hold, 106 pending. Voided: 108,
    # its payment failed.
    (["-m", "all_orders", "-d", "orders.financial_status", "-o", "orders.financial_status"],
     [{"financial_status": "paid", "all_orders": 6}, {"financial_status": "partially_refunded", "all_orders": 3},
      {"financial_status": "refunded", "all_orders": 1}, {"financial_status": "unpaid", "all_orders": 2},
      {"financial_status": "voided", "all_orders": 1}]),
    # Completed orders are fulfilled: 101, 104, 109, 112, 113. The rest are
    # not, processing 103, 110 and 117 and refunded 111 among them.
    (["-m", "all_orders", "-d", "orders.fulfillment_status", "-o", "orders.fulfillment_status"],
     [{"fulfillment_status": "fulfilled", "all_orders": 5}, {"fulfillment_status": "unfulfilled", "all_orders": 8}]),
    # The customer's orders by date placed, as Analytics ranks them, orders
    # of excluded statuses skipped: customer 1's 101, 104, 109, 111, 117;
    # customer 2's 103, 110, 113 (cancelled 107 skipped; counting it, 110
    # and 113 would be 3 and 4). Guest 112 has no number.
    (["-m", "orders", "-m", "revenue", "-d", "orders.customer_order_number", "-o", "orders.customer_order_number"],
     [{"customer_order_number": 1, "orders": 2, "revenue": 121},
      {"customer_order_number": 2, "orders": 2, "revenue": 116.4},
      {"customer_order_number": 3, "orders": 2, "revenue": 47.3},
      {"customer_order_number": 4, "orders": 1, "revenue": 33},
      {"customer_order_number": 5, "orders": 1, "revenue": 66},
      {"customer_order_number": None, "orders": 1, "revenue": 66}]),
    # New: 101 and 103. Repeat: 104 70.40, 109 30.80, 110 46, 111 33, 113
    # 16.50, 117 66 = 262.70. None: guest 112.
    (["-m", "orders", "-m", "revenue", "-d", "orders.new_vs_repeat", "-o", "orders.new_vs_repeat"],
     [{"new_vs_repeat": "new", "orders": 2, "revenue": 121},
      {"new_vs_repeat": "repeat", "orders": 6, "revenue": 262.7},
      {"new_vs_repeat": None, "orders": 1, "revenue": 66}]),
    # Repeat orders over the counted orders with a customer: 6 / 8.
    (["-m", "repeat_order_share"], [{"repeat_order_share": 6 / 8}]),
    # Lines of the counted orders: 101 2 mugs (1 before its edit) + 1 tee,
    # 103 1, 104 2, 109 1 (its removed sticker line gone), 110 1, 111 1, 112
    # 2, 113 2, 117 2 = 15 items; 13 left after 104's refunded tee and 111's
    # mug. A refund's own lines (negative quantities) are not lines of goods:
    # with them 15 would be 13. Line totals without tax: 40 + 30 + 25 + 54 +
    # 20 + 31.818182 + 20 + 60 + 10 + 50 (117's 45 EUR) = 340.818182; the
    # orders' subtotal is 338.82 with 109's fees of -2.
    (["-m", "items_sold", "-m", "items_net", "-m", "line_revenue", "-m", "items_per_order"],
     [{"items_sold": 15, "items_net": 13, "line_revenue": 340.818182, "items_per_order": 15 / 9}]),
    # Top SKU by items: MUG 2 (101) + 1 (109) + 1 (111) + 2 (117) = 6. A
    # line keeps no SKU; it gets its product's current one, the variation's
    # for a tee: TEE-M 4, TEE-L 2. The sticker has none and the cap was
    # deleted: 3 items without a SKU.
    (["-m", "items_sold", "-d", "order_lines.sku", "-o", "items_sold desc", "-l", "2"],
     [{"sku": "MUG", "items_sold": 6}, {"sku": "TEE-M", "items_sold": 4}]),
    # By shipping country: CA 110 46; DE 117 66; US 101, 103, 104, 109, 111,
    # 113 = 271.70; no shipping address 112 (billing only), 66.
    (["-m", "orders", "-m", "revenue", "-d", "orders.shipping_country", "-o", "orders.shipping_country"],
     [{"shipping_country": "CA", "orders": 1, "revenue": 46},
      {"shipping_country": "DE", "orders": 1, "revenue": 66},
      {"shipping_country": "US", "orders": 6, "revenue": 271.7},
      {"shipping_country": None, "orders": 1, "revenue": 66}]),
    # Every amount is in the store's currency, 117 converted: one currency.
    (["-m", "orders", "-d", "orders.currency"], [{"currency": "USD", "orders": 9}]),
    # Without a plugin's number, the order number is the id: 101's meta
    # holds a plugin's 1, which the package reads only when told its key.
    (["-m", "orders", "-d", "orders.order_number", "-f", "orders.order_id = 101"],
     [{"order_number": "101", "orders": 1}]),
]


if __name__ == "__main__":
    check(MODEL, CASES)
