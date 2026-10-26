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
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "orders.refunded_amount",
      "-m", "sales_events.net_revenue", "-m", "orders.refund_rate",
      "-m", "orders.average_order_value", "-m", "orders.discount_amount",
      "-m", "orders.shipping_amount", "-m", "orders.tax_amount", "-m", "orders.customers"],
     [{"orders.order_count": 9, "orders.revenue": 449.7, "orders.refunded_amount": 67.7,
       "sales_events.net_revenue": 382, "orders.refund_rate": 67.7 / 449.7,
       "orders.average_order_value": 338.82 / 9, "orders.discount_amount": 6,
       "orders.shipping_amount": 70, "orders.tax_amount": 40.88, "orders.customers": 2}]),
    # Every row of orders, counted or not: the 9 above and 102 (16.50), 106
    # (22), 107 (44), 108 (33): 13 orders, 565.20. Not 16: the trash, the
    # checkout draft and the deleted order are not orders.
    (["-m", "orders.all_orders", "-m", "orders.all_orders_total"],
     [{"orders.all_orders": 13, "orders.all_orders_total": 565.2}]),
    # Orders waiting for payment: 102 on hold (16.50) and 106 pending (22).
    # The counted metrics have none: orders would answer 0.
    (["-m", "orders.all_orders", "-m", "orders.all_orders_total",
      "-f", "orders.financial_status = 'unpaid'"],
     [{"orders.all_orders": 2, "orders.all_orders_total": 38.5}]),
    # Which rows the reports count.
    (["-m", "orders.all_orders", "-d", "orders.in_sales_reports", "-o", "orders.in_sales_reports"],
     [{"in_sales_reports": False, "orders.all_orders": 4},
      {"in_sales_reports": True, "orders.all_orders": 9}]),
    # By month of payment in New York. August: 101 88, 103 33 (September in
    # UTC). September: 104 70.40 (August by date placed), 109 30.80, 110 46,
    # 111 33; net 180.20 - 29.70 - 33 = 117.50, refunds by the month of their
    # order, 104's refund of October 5 included. October: 112 66, 113 16.50
    # (October 3 if dated when placed, and not counted in its earlier
    # version), 117 66; net 148.50 - 5.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-m", "sales_events.net_revenue",
      "-m", "orders.refunded_amount", "-d", "orders.order_month", "-o", "orders.order_month"],
     [{"order_month": "2026-08-01", "orders.order_count": 2, "orders.revenue": 121,
       "sales_events.net_revenue": 121, "orders.refunded_amount": 0},
      {"order_month": "2026-09-01", "orders.order_count": 4, "orders.revenue": 180.2,
       "sales_events.net_revenue": 117.5, "orders.refunded_amount": 62.7},
      {"order_month": "2026-10-01", "orders.order_count": 3, "orders.revenue": 148.5,
       "sales_events.net_revenue": 143.5, "orders.refunded_amount": 5}]),
    # Paid before midnight of September 1, a time without an offset, which is
    # read in the zone the model is served in, New York: August's 101 88 and
    # 103 33 (22:10 on August 31). Served in UTC, 103 (02:10 on September 1
    # there) is not there: 1 order, 88. A plain string reads as the TIMESTAMP
    # literal does.
    (["-m", "orders.order_count", "-m", "orders.revenue",
      "-f", "orders.order_time < TIMESTAMP '2026-09-01 00:00:00'"],
     [{"orders.order_count": 2, "orders.revenue": 121}]),
    (["-m", "orders.order_count", "-m", "orders.revenue",
      "-f", "orders.order_time < '2026-09-01 00:00:00'"],
     [{"orders.order_count": 2, "orders.revenue": 121}]),
    # Sales by the month they happened, as the store's reports count them:
    # each order in the month of its payment, each refund in its own month.
    # August 101 88 + 103 33 = 121. September 104 70.40 + 109 30.80 + 110
    # 46 + 111 33 - refund 902 33 = 147.20. October 112 66 + 113 16.50 +
    # 117 66 - 903 5 - 901 29.70 = 113.80. 382 in all, as net_revenue by
    # the month of the order above (121, 117.50, 143.50), where 901 is
    # September's. Refund 904 of cancelled 107 would take 22 off September.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_month",
      "-o", "sales_events.event_month"],
     [{"event_month": "2026-08-01", "sales_events.net_revenue": 121},
      {"event_month": "2026-09-01", "sales_events.net_revenue": 147.2},
      {"event_month": "2026-10-01", "sales_events.net_revenue": 113.8}]),
    # The same sales by kind of event: the 9 counted orders, 449.70, less
    # their refunds, 67.70. WooCommerce has no cancellation events: a
    # cancelled order is left out by its status.
    (["-m", "sales_events.net_revenue", "-d", "sales_events.event_type",
      "-o", "sales_events.event_type"],
     [{"event_type": "order", "sales_events.net_revenue": 449.7},
      {"event_type": "refund", "sales_events.net_revenue": -67.7}]),
    # Refunds by the month they were made: 902 (111, 33) on September 22;
    # 903 (112, 5, an amount without lines) on October 2 and 901 (104,
    # 29.70) on October 5. 904 (107, 22, September 10) is a refund of an
    # order the reports leave out, and they leave it out too: with it
    # September would be 2 refunds, 55.
    (["-m", "refund_count", "-m", "refunds_total", "-d", "refunds.refund_month",
      "-o", "refunds.refund_month"],
     [{"refund_month": "2026-09-01", "refund_count": 1, "refunds_total": 33},
      {"refund_month": "2026-10-01", "refund_count": 2, "refunds_total": 34.7}]),
    # Payment state of every row. Paid: 101, 103, 109, 110, 113 (its
    # earlier version, processing without a payment date, would be unpaid),
    # 117. Partially refunded: 104, 112, and 107, paid before it was
    # cancelled and refunded in part after. Refunded: 111. Unpaid: 102 on hold, 106 pending. Voided: 108,
    # its payment failed.
    (["-m", "orders.all_orders", "-d", "orders.financial_status", "-o", "orders.financial_status"],
     [{"financial_status": "paid", "orders.all_orders": 6},
      {"financial_status": "partially_refunded", "orders.all_orders": 3},
      {"financial_status": "refunded", "orders.all_orders": 1},
      {"financial_status": "unpaid", "orders.all_orders": 2},
      {"financial_status": "voided", "orders.all_orders": 1}]),
    # Completed orders are fulfilled: 101, 104, 109, 112, 113. The rest are
    # not, processing 103, 110 and 117 and refunded 111 among them.
    (["-m", "orders.all_orders", "-d", "orders.fulfillment_status",
      "-o", "orders.fulfillment_status"],
     [{"fulfillment_status": "fulfilled", "orders.all_orders": 5},
      {"fulfillment_status": "unfulfilled", "orders.all_orders": 8}]),
    # The customer's orders by date placed, as Analytics ranks them, orders
    # of excluded statuses skipped: customer 1's 101, 104, 109, 111, 117;
    # customer 2's 103, 110, 113 (cancelled 107 skipped; counting it, 110
    # and 113 would be 3 and 4). Guest 112 has no number.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-d", "orders.customer_order_number",
      "-o", "orders.customer_order_number"],
     [{"customer_order_number": 1, "orders.order_count": 2, "orders.revenue": 121},
      {"customer_order_number": 2, "orders.order_count": 2, "orders.revenue": 116.4},
      {"customer_order_number": 3, "orders.order_count": 2, "orders.revenue": 47.3},
      {"customer_order_number": 4, "orders.order_count": 1, "orders.revenue": 33},
      {"customer_order_number": 5, "orders.order_count": 1, "orders.revenue": 66},
      {"customer_order_number": None, "orders.order_count": 1, "orders.revenue": 66}]),
    # New: 101 and 103. Repeat: 104 70.40, 109 30.80, 110 46, 111 33, 113
    # 16.50, 117 66 = 262.70. None: guest 112.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-d", "orders.new_vs_repeat",
      "-o", "orders.new_vs_repeat"],
     [{"new_vs_repeat": "new", "orders.order_count": 2, "orders.revenue": 121},
      {"new_vs_repeat": "repeat", "orders.order_count": 6, "orders.revenue": 262.7},
      {"new_vs_repeat": None, "orders.order_count": 1, "orders.revenue": 66}]),
    # Repeat orders over the counted orders with a customer: 6 / 8.
    (["-m", "orders.repeat_order_share"],
     [{"orders.repeat_order_share": 6 / 8}]),
    # Lines of the counted orders: 101 2 mugs (1 before its edit) + 1 tee,
    # 103 1, 104 2, 109 1 (its removed sticker line gone), 110 1, 111 1, 112
    # 2, 113 2, 117 2 = 15 items; 13 left after 104's refunded tee and 111's
    # mug. A refund's own lines (negative quantities) are not lines of goods:
    # with them 15 would be 13. Line totals without tax: 40 + 30 + 25 + 54 +
    # 20 + 31.818182 + 20 + 60 + 10 + 50 (117's 45 EUR) = 340.818182; the
    # orders' subtotal is 338.82 with 109's fees of -2.
    (["-m", "items_sold", "-m", "items_net", "-m", "line_revenue", "-m", "orders.items_per_order"],
     [{"items_sold": 15, "items_net": 13, "line_revenue": 340.818182,
       "orders.items_per_order": 15 / 9}]),
    # Top SKU by items: MUG 2 (101) + 1 (109) + 1 (111) + 2 (117) = 6. A
    # line keeps no SKU; it gets its product's current one, the variation's
    # for a tee: TEE-M 4, TEE-L 2. The sticker has none and the cap was
    # deleted: 3 items without a SKU.
    (["-m", "items_sold", "-d", "order_lines.sku", "-o", "items_sold desc", "-l", "2"],
     [{"sku": "MUG", "items_sold": 6},
      {"sku": "TEE-M", "items_sold": 4}]),
    # By shipping country: CA 110 46; DE 117 66; US 101, 103, 104, 109, 111,
    # 113 = 271.70; no shipping address 112 (billing only), 66.
    (["-m", "orders.order_count", "-m", "orders.revenue", "-d", "orders.shipping_country",
      "-o", "orders.shipping_country"],
     [{"shipping_country": "CA", "orders.order_count": 1, "orders.revenue": 46},
      {"shipping_country": "DE", "orders.order_count": 1, "orders.revenue": 66},
      {"shipping_country": "US", "orders.order_count": 6, "orders.revenue": 271.7},
      {"shipping_country": None, "orders.order_count": 1, "orders.revenue": 66}]),
    # Every amount is in the store's currency, 117 converted: one currency.
    (["-m", "orders.order_count", "-d", "orders.currency"],
     [{"currency": "USD", "orders.order_count": 9}]),
    # Without a plugin's number, the order number is the id: 101's meta
    # holds a plugin's 1, which the package reads only when told its key.
    (["-m", "orders.order_count", "-d", "orders.order_number", "-f", "orders.order_id = 101"],
     [{"order_number": "101", "orders.order_count": 1}]),
    # Products. Lines of the counted orders as in line_revenue above, each
    # in every one of its product's latest categories and brands; returns
    # are the refunds' lines (904's, of cancelled 107, left out with its
    # order), by the month of the order: 104's tee 27 and 111's mug 20, 2
    # items, 47; net 340.818182 - 47 = 293.818182.
    (["-m", "items_returned", "-m", "line_returned_amount", "-m", "line_net_revenue"],
     [{"items_returned": 2, "line_returned_amount": 47, "line_net_revenue": 293.818182}]),
    # By category, the product's own ones, as Analytics' Categories report
    # counts them; a category is told apart by its path, as two are named
    # Accessories. Gifts, Kitchen & Dining and Kitchen & Dining >
    # Accessories all have the Mug, 40 + 20 + 20 + 50 = 130 over 6 items,
    # 111's mug returned (20): net 110 each. Clothing > T-Shirts the Tee, 30
    # + 54 + 31.818182 + 60 = 175.818182 over 6 items, 104's tee returned
    # (27): net 148.818182. Uncategorized the Sticker pack, 113's 10 over 2
    # items (102 is on hold, not counted); it is in the trash now and keeps
    # its terms. None: the Cap (deleted, its terms gone with it), 25.
    # Clothing and Clothing > Accessories have nothing: the Tote never
    # sold. The categories add up to 600.818182, the Mug's 130 twice more
    # than line_revenue's 340.818182. Read with the old name, Kitchen would
    # have the Mug's 130; with the Sticker's old link, Gifts would have 140
    # over 8 items; joined on term_id, the Sticker pack's 10 would be in
    # Accessories and no other line would have a category.
    (["-m", "category_items_sold", "-m", "category_revenue", "-m", "category_items_returned",
      "-m", "category_returned_amount", "-m", "category_net_revenue",
      "-d", "line_categories.category_path", "-f", "line_categories.is_direct = true",
      "-o", "line_categories.category_path"],
     [{"category_path": "Clothing > T-Shirts", "category_items_sold": 6,
       "category_revenue": 175.818182, "category_items_returned": 1,
       "category_returned_amount": 27, "category_net_revenue": 148.818182},
      {"category_path": "Gifts", "category_items_sold": 6, "category_revenue": 130,
       "category_items_returned": 1, "category_returned_amount": 20, "category_net_revenue": 110},
      {"category_path": "Kitchen & Dining", "category_items_sold": 6, "category_revenue": 130,
       "category_items_returned": 1, "category_returned_amount": 20, "category_net_revenue": 110},
      {"category_path": "Kitchen & Dining > Accessories", "category_items_sold": 6,
       "category_revenue": 130, "category_items_returned": 1, "category_returned_amount": 20,
       "category_net_revenue": 110},
      {"category_path": "Uncategorized", "category_items_sold": 2, "category_revenue": 10,
       "category_items_returned": 0, "category_returned_amount": 0, "category_net_revenue": 10},
      {"category_path": None, "category_items_sold": 1, "category_revenue": 25,
       "category_items_returned": 0, "category_returned_amount": 0, "category_net_revenue": 25}]),
    # With subcategories, as Analytics' filter by category takes them, each
    # line once: Clothing the Tee through T-Shirts, 175.818182 over 6 items,
    # net 148.818182; Kitchen & Dining the Mug, 130 over 6, net 110, not 260
    # over 12 for its two categories there. Read with T-Shirts' parent
    # before September 10 (none), or with the parent matched to
    # term_taxonomy_id, Clothing would have nothing.
    (["-m", "category_items_sold", "-m", "category_revenue", "-m", "category_net_revenue",
      "-d", "line_categories.category_path",
      "-f", "line_categories.category_path IN ('Clothing', 'Kitchen & Dining')",
      "-o", "line_categories.category_path"],
     [{"category_path": "Clothing", "category_items_sold": 6, "category_revenue": 175.818182,
       "category_net_revenue": 148.818182},
      {"category_path": "Kitchen & Dining", "category_items_sold": 6, "category_revenue": 130,
       "category_net_revenue": 110}]),
    # September by category: Gifts, Kitchen & Dining and its Accessories
    # 109's 20 + 111's 20 = 40, net 20 each; T-Shirts 104's 54 + 110's
    # 31.818182 = 85.818182, net 58.818182.
    (["-m", "category_revenue", "-m", "category_net_revenue", "-d", "line_categories.category_path",
      "-f", "line_categories.is_direct = true", "-f", "orders.order_month = DATE '2026-09-01'",
      "-o", "line_categories.category_path"],
     [{"category_path": "Clothing > T-Shirts", "category_revenue": 85.818182,
       "category_net_revenue": 58.818182},
      {"category_path": "Gifts", "category_revenue": 40, "category_net_revenue": 20},
      {"category_path": "Kitchen & Dining", "category_revenue": 40, "category_net_revenue": 20},
      {"category_path": "Kitchen & Dining > Accessories", "category_revenue": 40,
       "category_net_revenue": 20}]),
    # By brand: Acme the Tee and the Sticker pack, 175.818182 + 10 =
    # 185.818182 over 8 items, 1 returned for 27; Northwind the Tee,
    # 175.818182 over 6, 1 returned for 27; none the Mug and the Cap, 130 +
    # 25 = 155 over 7, 1 returned for 20. Beta, deleted, has nothing; read
    # with it, it would have the Tee's 175.818182.
    (["-m", "brand_items_sold", "-m", "brand_revenue", "-m", "brand_items_returned",
      "-m", "brand_returned_amount", "-m", "brand_net_revenue", "-d", "line_brands.brand",
      "-o", "line_brands.brand"],
     [{"brand": "Acme", "brand_items_sold": 8, "brand_revenue": 185.818182, "brand_items_returned": 1,
       "brand_returned_amount": 27, "brand_net_revenue": 158.818182},
      {"brand": "Northwind", "brand_items_sold": 6, "brand_revenue": 175.818182,
       "brand_items_returned": 1, "brand_returned_amount": 27, "brand_net_revenue": 148.818182},
      {"brand": None, "brand_items_sold": 7, "brand_revenue": 155, "brand_items_returned": 1,
       "brand_returned_amount": 20, "brand_net_revenue": 135}]),
    # Brand by month: Acme August 30 (101's tee), September 85.818182,
    # October 60 + 10 = 70; Northwind August 30, September 85.818182,
    # October 60; none August 40 + 25 = 65, September 40, October 50.
    (["-m", "brand_revenue", "-d", "line_brands.brand", "-d", "orders.order_month",
      "-o", "line_brands.brand", "-o", "orders.order_month"],
     [{"brand": "Acme", "order_month": "2026-08-01", "brand_revenue": 30},
      {"brand": "Acme", "order_month": "2026-09-01", "brand_revenue": 85.818182},
      {"brand": "Acme", "order_month": "2026-10-01", "brand_revenue": 70},
      {"brand": "Northwind", "order_month": "2026-08-01", "brand_revenue": 30},
      {"brand": "Northwind", "order_month": "2026-09-01", "brand_revenue": 85.818182},
      {"brand": "Northwind", "order_month": "2026-10-01", "brand_revenue": 60},
      {"brand": None, "order_month": "2026-08-01", "brand_revenue": 65},
      {"brand": None, "order_month": "2026-09-01", "brand_revenue": 40},
      {"brand": None, "order_month": "2026-10-01", "brand_revenue": 50}]),
    # Average order value of the orders with a line in Gifts, each order
    # once, all of its goods: the Mug's orders 101 70 (its tee included),
    # 109 18 (with its fees), 111 20, 117 50 = 158 over 4; counted once per
    # category of the line, Gifts or Kitchen & Dining would give 316 over 8.
    # Clothing, with its subcategories: 101 70, 104 54, 110 31.82, 112 60 =
    # 215.82 over 4, the same as T-Shirts.
    (["-m", "orders.average_order_value", "-m", "orders.order_count",
      "-f", "line_categories.category_path = 'Gifts'"],
     [{"orders.average_order_value": 158 / 4, "orders.order_count": 4}]),
    (["-m", "orders.average_order_value", "-m", "orders.order_count",
      "-f", "line_categories.category_path = 'Clothing'"],
     [{"orders.average_order_value": 215.82 / 4, "orders.order_count": 4}]),
    # Catalog: 4 products (11, 12, 15, 16); the Cap is deleted, the Sticker
    # pack (13) and the Notebook (17) are in the trash, and the variations
    # 121 and 122, the page and the orders' placeholders are no products.
    # Active (published) 3, draft 1 (16).
    (["-m", "products.product_count", "-d", "products.status", "-o", "products.status"],
     [{"status": "active", "products.product_count": 3},
      {"status": "draft", "products.product_count": 1}]),
    # Active by category: Clothing > Accessories 1 (15), Clothing > T-Shirts
    # 1 (12), Gifts 2 (11, 15), Kitchen & Dining 1 (11), Kitchen & Dining >
    # Accessories 1 (11); by name, Accessories would have 2. With
    # subcategories, Clothing has 2 (12, 15), and Kitchen & Dining 1 (11, in
    # it twice).
    (["-m", "product_categories.product_count", "-d", "product_categories.category_path",
      "-f", "products.status = 'active'", "-f", "product_categories.is_direct = true",
      "-o", "product_categories.category_path"],
     [{"category_path": "Clothing > Accessories", "product_categories.product_count": 1},
      {"category_path": "Clothing > T-Shirts", "product_categories.product_count": 1},
      {"category_path": "Gifts", "product_categories.product_count": 2},
      {"category_path": "Kitchen & Dining", "product_categories.product_count": 1},
      {"category_path": "Kitchen & Dining > Accessories", "product_categories.product_count": 1}]),
    (["-m", "product_categories.product_count", "-d", "product_categories.category_path",
      "-f", "products.status = 'active'",
      "-f", "product_categories.category_path IN ('Clothing', 'Kitchen & Dining')",
      "-o", "product_categories.category_path"],
     [{"category_path": "Clothing", "product_categories.product_count": 2},
      {"category_path": "Kitchen & Dining", "product_categories.product_count": 1}]),
    # By brand: Acme the Tee and the Tote (the Sticker pack is in the
    # trash), Northwind the Tee.
    (["-m", "product_brands.product_count", "-d", "product_brands.brand", "-o", "product_brands.brand"],
     [{"brand": "Acme", "product_brands.product_count": 2},
      {"brand": "Northwind", "product_brands.product_count": 1}]),
    # Last sold, by the order's date: Mug October 9 (117), Tee October 1
    # (112); never sold: 15, 16. The Sticker pack's October 6 (113) is out
    # with it, and 114 (trash) and 116 (deleted) do not count.
    (["-d", "products.product_id", "-d", "products.last_sold_date", "-o", "products.product_id"],
     [{"product_id": 11, "last_sold_date": "2026-10-09"},
      {"product_id": 12, "last_sold_date": "2026-10-01"},
      {"product_id": 15, "last_sold_date": None},
      {"product_id": 16, "last_sold_date": None}]),
]

if __name__ == "__main__":
    check(MODEL, CASES)
