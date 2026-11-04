# Shopify package

Maps a Shopify store's orders and catalog, read from the
[GraphQL Admin API](https://shopify.dev/docs/api/admin-graphql), onto the
`commerce` entities: `orders`, `order_lines`, `refunds`, `sales_events`,
`customers`, `products`, `line_categories`, `line_brands`,
`product_categories` and `product_brands`. What the model answers and
how it defines sales, categories and customers:
[docs/commerce.md](../../docs/commerce.md). Installing the package in a
dbt project, time zones and several stores:
[docs/deployment.md](../../docs/deployment.md).

## Quick start

There is no public Shopify export, so try the package on the rows the
repository tests it with,
[`tests/shopify/fixture.sql`](../../tests/shopify/fixture.sql): twelve orders
of a shop in New York and its thirteen products, each a case the package
must get right (refunds, cancellations, discounts, tax included in
prices, a gift card, a tip, import duties, repeated deliveries, a
product's type and vendor changed, a deleted product). You need ClickHouse, dbt and
dactopus-ossie-clickhouse, as in the README's [Quick start](../../README.md#quick-start).

1. **Load** the package's input tables
   [`sources/shopify/input.sql`](input.sql) and the rows.
   Their database is a parameter; the package reads it from the dbt
   variable `shopify_input_database` (default `shopify_raw`, kept here
   for your own store). The input has no label: the package writes the
   store's label into every row it builds, from the dbt variable
   `shopify_source_id` (default `shopify`; [several
   stores](../../docs/deployment.md#several-stores-properties-or-networks)).

   ```bash
   clickhouse client --param_db=shopify_sample_raw --multiquery < sources/shopify/input.sql
   clickhouse client --param_db=shopify_sample_raw --multiquery < tests/shopify/fixture.sql
   ```

2. **Build** into a database of its own, in the shop's time zone. Order
   and refund dates are in it, as in Shopify's reports; the package's
   default is UTC.

   ```bash
   CLICKHOUSE_DATABASE=shopify_sample dbt build --project-dir sources/shopify \
       --vars '{shopify_input_database: shopify_sample_raw, shopify_timezone: America/New_York}'
   ```

3. **Validate** the model and **check** its answers: `check_numbers.py`
   asks 42 questions through dactopus-ossie-clickhouse, in the zone of
   step 2, and compares the answers with numbers worked out by hand from
   the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/commerce.yaml --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/shopify_sample OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York python3 tests/shopify/check_numbers.py
   ```

4. **Ask.** Serve `entities/commerce.yaml` in the zone of step 2, so
   that "today" in a question is the shop's date. Try net revenue,
   refunds by month, average order value and repeat orders, by shipping
   country and new or returning customer; revenue and returns by product
   type and by vendor; products not sold since a date.

   ```bash
   dactopus-ossie-clickhouse serve entities/commerce.yaml \
       --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   ```

## Your store

1. **An app.** In the Shopify
   [Dev Dashboard](https://shopify.dev/docs/apps/build/dev-dashboard/create-apps-using-dev-dashboard),
   create an app with the scopes `read_orders`, `read_customers` and
   `read_products`, and install it on the store. Shopify returns only the
   last 60 days of orders unless the app also has `read_all_orders`,
   which Shopify grants on request
   ([Order](https://shopify.dev/docs/api/admin-rest/latest/resources/order)).
   Get an access token with the
   [client credentials grant](https://shopify.dev/docs/apps/build/authentication-authorization/client-credentials-grant);
   it lasts 24 hours:

   ```bash
   curl -s -X POST "https://$SHOPIFY_SHOP.myshopify.com/admin/oauth/access_token" \
       --data-urlencode grant_type=client_credentials \
       --data-urlencode "client_id=$SHOPIFY_CLIENT_ID" \
       --data-urlencode "client_secret=$SHOPIFY_CLIENT_SECRET"
   ```

2. **Export** the orders and products updated since a time. Save the
   script below as `export_shopify.py` and run it with the store's
   subdomain and the token; the first time, from a date before the
   store's first order:

   ```bash
   SHOPIFY_SHOP=<store> SHOPIFY_TOKEN=<token> uv run --with certifi export_shopify.py 2000-01-01T00:00:00Z data/shopify
   ```

   It reads the GraphQL Admin API (version 2026-10) 25 orders at a
   time, each with its lines and refunds, then the products, archived
   ones and drafts included, and writes one JSON file per input table,
   with only the columns `input.sql` declares. A deleted product is gone
   from the API: the script finds it in the store's events (`destroy` of
   a `PRODUCT`) and writes a version of it with only its id and the time
   of the deletion. It needs
   [uv](https://docs.astral.sh/uv/) for the one package it uses,
   `certifi`: Python from python.org on macOS does not see the system's
   root certificates. A Shopify bulk operation would be faster on a large store, but
   it cannot read refund lines, which sit inside the list of an order's
   refunds.

   <details><summary>export_shopify.py</summary>

   ```python
   import json, os, pathlib, ssl, sys, time, urllib.request
   from decimal import Decimal
   import certifi

   shop, token = os.environ["SHOPIFY_SHOP"], os.environ["SHOPIFY_TOKEN"]
   since, out = sys.argv[1], pathlib.Path(sys.argv[2])
   API = f"https://{shop}.myshopify.com/admin/api/2026-10/graphql.json"
   TLS = ssl.create_default_context(cafile=certifi.where())
   MONEY = "{ shopMoney { amount } }"
   QUERY = f"""query ($cursor: String, $filter: String) {{
     orders(first: 25, after: $cursor, query: $filter, sortKey: UPDATED_AT) {{
       pageInfo {{ hasNextPage endCursor }}
       nodes {{
         legacyResourceId name createdAt processedAt updatedAt cancelledAt closedAt test
         customer {{ legacyResourceId }} email currencyCode presentmentCurrencyCode
         displayFinancialStatus displayFulfillmentStatus sourceName taxesIncluded
         totalPriceSet {MONEY} totalTaxSet {MONEY} totalRefundedSet {MONEY}
         currentTotalPriceSet {MONEY} totalTipReceivedSet {MONEY}
         originalTotalDutiesSet {MONEY} originalTotalAdditionalFeesSet {MONEY}
         discountCodes shippingAddress {{ countryCodeV2 provinceCode city zip }}
         shippingLines(first: 50) {{ pageInfo {{ hasNextPage }} nodes {{
           discountedPriceSet {MONEY} taxLines {{ priceSet {MONEY} }} }} }}
         lineItems(first: 50) {{ pageInfo {{ hasNextPage }} nodes {{
           id product {{ legacyResourceId }} variant {{ legacyResourceId }}
           sku title variantTitle quantity currentQuantity
           originalUnitPriceSet {MONEY} originalTotalSet {MONEY}
           discountAllocations {{ allocatedAmountSet {MONEY} }}
           taxLines {{ rate priceSet {MONEY} }} taxable requiresShipping isGiftCard }} }}
         refunds {{
           legacyResourceId createdAt processedAt updatedAt note totalRefundedSet {MONEY}
           refundLineItems(first: 50) {{ pageInfo {{ hasNextPage }} nodes {{
             id lineItem {{ id }} quantity restockType subtotalSet {MONEY} totalTaxSet {MONEY} }} }} }}
       }}
     }}
   }}"""
   PRODUCTS = """query ($cursor: String, $filter: String) {
     products(first: 100, after: $cursor, query: $filter, sortKey: UPDATED_AT) {
       pageInfo { hasNextPage endCursor }
       nodes { legacyResourceId title productType vendor status isGiftCard updatedAt }
     }
   }"""
   DELETED = """query ($cursor: String, $filter: String) {
     events(first: 100, after: $cursor, query: $filter, sortKey: CREATED_AT) {
       pageInfo { hasNextPage endCursor }
       nodes { createdAt ... on BasicEvent { subjectId } }
     }
   }"""


   def fetch(query, field, variables):
       while True:
           req = urllib.request.Request(API, json.dumps({"query": query, "variables": variables}).encode(),
                                        {"X-Shopify-Access-Token": token, "Content-Type": "application/json"})
           body = json.load(urllib.request.urlopen(req, context=TLS))
           if any(e.get("extensions", {}).get("code") == "THROTTLED" for e in body.get("errors", [])):
               time.sleep(2)
               continue
           if "errors" in body:
               sys.exit(body["errors"])
           return body["data"][field]


   def pages(query, field, filter):
       page = {"pageInfo": {"hasNextPage": True, "endCursor": None}}
       while page["pageInfo"]["hasNextPage"]:
           page = fetch(query, field, {"cursor": page["pageInfo"]["endCursor"], "filter": filter})
           yield from page["nodes"]


   def money(v): return str(Decimal(v["shopMoney"]["amount"])) if v else "0"
   def total(items, key): return str(sum((Decimal(i[key]["shopMoney"]["amount"]) for i in items), Decimal(0)))
   def legacy(gid): return int(gid.rsplit("/", 1)[1])
   def ts(v): return v and v.replace("T", " ").rstrip("Z")
   def nodes(conn, what):
       if conn["pageInfo"]["hasNextPage"]:
           sys.exit(f"more than 50 {what} in one order or refund: raise first: in the query")
       return conn["nodes"]


   tables = {t: [] for t in ("orders", "order_lines", "refunds", "refund_lines", "products")}
   for o in pages(QUERY, "orders", f"updated_at:>='{since}'"):
       oid, updated, ship = int(o["legacyResourceId"]), ts(o["updatedAt"]), nodes(o["shippingLines"], "shipping lines")
       addr = o["shippingAddress"] or {}
       tables["orders"].append({
           "id": oid, "name": o["name"], "created_at": ts(o["createdAt"]), "processed_at": ts(o["processedAt"]),
           "updated_at": updated, "cancelled_at": ts(o["cancelledAt"]), "closed_at": ts(o["closedAt"]),
           "test": o["test"], "customer_id": o["customer"] and int(o["customer"]["legacyResourceId"]),
           "email": o["email"], "currency_code": o["currencyCode"],
           "presentment_currency_code": o["presentmentCurrencyCode"],
           "display_financial_status": o["displayFinancialStatus"],
           "display_fulfillment_status": o["displayFulfillmentStatus"],
           "source_name": o["sourceName"], "taxes_included": o["taxesIncluded"],
           "total_price": money(o["totalPriceSet"]), "shipping_price": total(ship, "discountedPriceSet"),
           "shipping_tax": total([t for s in ship for t in s["taxLines"]], "priceSet"),
           "total_tax": money(o["totalTaxSet"]), "total_refunded": money(o["totalRefundedSet"]),
           "current_total_price": money(o["currentTotalPriceSet"]), "total_tip": money(o["totalTipReceivedSet"]),
           "total_duties": money(o["originalTotalDutiesSet"]),
           "total_additional_fees": money(o["originalTotalAdditionalFeesSet"]),
           "discount_codes": o["discountCodes"], "shipping_country_code": addr.get("countryCodeV2"),
           "shipping_province_code": addr.get("provinceCode"), "shipping_city": addr.get("city"),
           "shipping_zip": addr.get("zip")})
       for l in nodes(o["lineItems"], "line items"):
           tables["order_lines"].append({
               "id": legacy(l["id"]), "order_id": oid, "order_updated_at": updated,
               "product_id": l["product"] and int(l["product"]["legacyResourceId"]),
               "variant_id": l["variant"] and int(l["variant"]["legacyResourceId"]),
               "sku": l["sku"], "title": l["title"], "variant_title": l["variantTitle"],
               "quantity": l["quantity"], "current_quantity": l["currentQuantity"],
               "original_unit_price": money(l["originalUnitPriceSet"]), "original_total": money(l["originalTotalSet"]),
               "discount_allocated": total(l["discountAllocations"], "allocatedAmountSet"),
               "total_tax": total(l["taxLines"], "priceSet"),
               "tax_rate": str(sum((Decimal(str(t["rate"])) for t in l["taxLines"]), Decimal(0))),
               "taxable": l["taxable"], "requires_shipping": l["requiresShipping"], "is_gift_card": l["isGiftCard"]})
       for r in o["refunds"]:
           rid, refund_updated = int(r["legacyResourceId"]), ts(r["updatedAt"])
           tables["refunds"].append({
               "id": rid, "order_id": oid, "created_at": ts(r["createdAt"]),
               "processed_at": ts(r["processedAt"]), "updated_at": refund_updated,
               "note": r["note"], "total_refunded": money(r["totalRefundedSet"])})
           for rl in nodes(r["refundLineItems"], "refund lines"):
               tables["refund_lines"].append({
                   "id": legacy(rl["id"]), "refund_id": rid, "refund_updated_at": refund_updated,
                   "line_item_id": legacy(rl["lineItem"]["id"]), "quantity": rl["quantity"],
                   "subtotal": money(rl["subtotalSet"]), "total_tax": money(rl["totalTaxSet"]),
                   "restock_type": rl["restockType"]})

   for p in pages(PRODUCTS, "products", f"updated_at:>='{since}'"):
       tables["products"].append({
           "id": int(p["legacyResourceId"]), "title": p["title"], "product_type": p["productType"],
           "vendor": p["vendor"], "status": p["status"], "is_gift_card": p["isGiftCard"],
           "updated_at": ts(p["updatedAt"])})
   for e in pages(DELETED, "events", f"subject_type:PRODUCT AND action:destroy AND created_at:>='{since}'"):
       tables["products"].append({"id": legacy(e["subjectId"]), "updated_at": ts(e["createdAt"]),
                                  "deleted_at": ts(e["createdAt"])})

   out.mkdir(parents=True, exist_ok=True)
   for name, rows in tables.items():
       (out / f"{name}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
       print(name, len(rows))
   ```

   </details>

3. **Load** the files into the input tables. A file is empty when
   nothing of its kind changed, often refunds, and ClickHouse refuses an
   empty insert, so the loop skips it:

   ```bash
   clickhouse client --param_db=shopify_raw --multiquery < sources/shopify/input.sql
   for t in orders order_lines refunds refund_lines products; do
       if [ -s data/shopify/$t.jsonl ]; then
           clickhouse client --query "INSERT INTO shopify_raw.$t FORMAT JSONEachRow" < data/shopify/$t.jsonl
       fi
   done
   ```

4. **Build** with the shop's time zone (Settings > General in the admin)
   as `shopify_timezone`, then validate and ask as above, with the same
   zone as `--time-zone`, at the database the tables went to
   (`CLICKHOUSE_DATABASE`, default `dactopus`).

5. **Next loads.** Export from an hour before the latest change already
   loaded, load, and build again: the build is incremental. A refund or a
   cancellation changes an order's `updated_at`, so the export delivers
   the order again, whole; delivering the same version twice is harmless.
   So does a change of a product, a sale included (Shopify updates its
   inventory), and its deletion arrives from the events of the same
   window.

   ```bash
   since=$(clickhouse client --query "SELECT formatDateTime(max(updated_at) - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%SZ') FROM shopify_raw.orders")
   SHOPIFY_SHOP=<store> SHOPIFY_TOKEN=<token> uv run --with certifi export_shopify.py "$since" data/shopify
   ```

   Orders deleted in Shopify are not exported again, so they stay in the
   input tables.


## Known differences from Shopify's reports

The package is checked against a store's reports.
`sales_events.net_revenue` equals Shopify's total sales overall, by
shipping country and by new or returning customer, and, by
`sales_events.event_date`, for each order on each day;
`orders.average_order_value` equals the store's. Units, goods revenue,
returns and net sales by product type and by vendor equal the reports'
over all time and by month, and the counts of products by status, type
and vendor equal the admin's. The customers, new customers and
returning customers of each month, each customer's total sales and
orders, and orders and customers by month and
`months_since_first_purchase` equal the reports'. Test orders are left
out, as in the reports. Other numbers differ by definition, and the model's
descriptions say how:

- **Gross and net sales** in Shopify's reports are goods only.
  `orders.revenue` and `sales_events.net_revenue` add shipping, tax and
  import duties; `order_lines.line_revenue` is goods after discounts.
- **Sales reversals** (formerly returns) in the reports are without tax
  and count a cancelled unpaid order as reversed.
  `orders.refunded_amount` is the money paid back, with its tax; a
  cancelled unpaid order has nothing refunded.
  `sales_events.net_revenue` takes a cancelled order back on the day it
  was cancelled, as the reports do, through a cancellation event.
- **Taxes** in the reports are net of refunded tax; `orders.tax_amount`
  is the tax on the order as placed.
- **Discounts** can differ on an order created through the API with its
  tax lines set on the price before the discount (10.00 against the
  report's 8.84 on the development store); on orders from the storefront
  they match.
- **A refunded tip** has no refund line, so it cannot be told from a
  refund of goods and counts as a refund
  ([#6](https://github.com/Dactopus/dactopus-data-models/issues/6)).
  Tips and gift cards sold are otherwise not sales, as in the reports.
- **Gift cards** count in the reports' units sold and returned; here a
  gift card is no product, so `order_lines.items_sold` and
  `order_lines.items_returned` leave it out.
- **Returns by product, type or vendor**: the reports date a return on
  the day of the refund, `order_lines.items_returned` and
  `order_lines.line_returned_amount` on the day of the order. Over all
  time they are equal.
- **Average order value by product type**: the reports, filtered by a
  type, count only that type's lines of each order;
  `orders.average_order_value` filtered by a category counts each such
  order whole, as WooCommerce Analytics does.

Known limits of the package: a custom item with no product, no tax and
nothing to ship that costs exactly the order's tip is taken for the tip;
a line's tax rates are added up, so compound taxes are not exact; orders
deleted in Shopify stay; amounts are in the shop's currency, not the
currency the customer paid in. In a shop whose prices include tax, a
line's discount is computed in cents, so in a currency without them,
such as the yen, `orders.discount_total` can carry a fraction
([#7](https://github.com/Dactopus/dactopus-data-models/issues/7)). The
reports date an order edit on the day of the edit, `sales_events` on the
day of the order; a cancellation and a refund of one order on different
days are not checked against the reports yet
([#16](https://github.com/Dactopus/dactopus-data-models/issues/16)).

The memory a build needs grows with the shop's history, slowly: on
synthetic shops of 2, 4 and 8 million orders, the largest query of the
first build, `orders`, peaks at 1.1, 1.5 and 2.0 GB, and the structural
test `orders_amounts_consistent` at 0.7, 1.7 and 2.7 GB, so on a server
that allows a query 3 GB it is the first to fail, past 8 million orders
([#8](https://github.com/Dactopus/dactopus-data-models/issues/8)).
The input tables' sorting keys (`input.sql`) are part of this: with
other keys the package builds the same tables, sorting each whole in
memory.
