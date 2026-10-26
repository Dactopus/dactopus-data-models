# dactopus-data-models

[![CI](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Dactopus/dactopus-data-models)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Dactopus/dactopus-data-models)](https://github.com/Dactopus/dactopus-data-models/releases)

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format, with IoT devices as a reference domain. Two kinds of content:

- **Canonical entities**: sessions, events and purchases from web
  analytics; orders, their lines, refunds and sales events, and the
  catalog's products with their categories and brands, from the store;
  devices and their readings, the reference domain `iot`. They
  have the same shape whatever the data came from.
- **Source packages**: each maps one source onto those entities. GA4,
  Shopify, WooCommerce and Sensor.Community are available.

What comes next is in [ROADMAP.md](ROADMAP.md).

The aim: a store on Shopify and a store on its own Postgres look the same
once both are mapped, and one query works on both. The same model serves
BI tools through ClickHouse tables and AI agents through
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse).

<a href="https://dactopus.github.io/dactopus-data-models/"><img src="docs/architecture.svg" width="680" alt="How the packages work: the GA4 export, Shopify's orders, a WooCommerce store's order tables and Sensor.Community's readings are loaded into input tables in your ClickHouse; the dbt packages build the canonical tables; BI tools read them directly and AI agents through dactopus-ossie-clickhouse and the Ossie models."></a>

Click the diagram for the [interactive version](https://dactopus.github.io/dactopus-data-models/):
what each part does and where it takes its settings from, and one
purchase followed from GA4 to an AI agent's answer.

## Sources

| Source | Entities | Status |
| --- | --- | --- |
| GA4 (BigQuery export) | `events`, `sessions`, `purchases` | available |
| Shopify (GraphQL Admin API) | `orders`, `order_lines`, `refunds`, `sales_events`, `products`, `line_categories`, `line_brands`, `product_categories`, `product_brands` | available |
| WooCommerce (the store's MySQL tables through CDC) | the same as Shopify | available |
| Sensor.Community (the archive's files and the API's snapshots) | `devices`, `readings` | available, reference domain |

Both order sources map onto the same entities. Where they differ, such as
which orders the store's reports count, the entities' descriptions say
how.

`iot` is a reference domain: its entities are drawn from one public
dataset, the readings of the [Sensor.Community](https://sensor.community/)
air quality network, and from no business's own data. A field goes into
them when any network of devices would have it with the same meaning
([Authoring rules](#authoring-rules)). No second source is planned for it.

## Quick start

Each walkthrough builds a package with dbt, which connects through a
profile named `dactopus`. A package ships none: add this one to
`~/.dbt/profiles.yml`, where dbt v2 and v1 look by default. It reads the
connection from `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP, default
8123), `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`, and the database the
tables go to from `CLICKHOUSE_DATABASE` (default `dactopus`). Over TLS,
as ClickHouse Cloud requires, add `secure: true` and set the HTTPS port,
and give dactopus-ossie-clickhouse an `https://` URL in place of the
`http://` ones below: it uses TLS whenever the URL is `https://`, on any
port.

```yaml
dactopus:
  target: default
  outputs:
    default:
      type: clickhouse
      # The database the canonical tables are written to.
      schema: "{{ env_var('CLICKHOUSE_DATABASE', 'dactopus') }}"
      host: "{{ env_var('CLICKHOUSE_HOST', 'localhost') }}"
      port: "{{ env_var('CLICKHOUSE_PORT', '8123') | int }}"
      user: "{{ env_var('CLICKHOUSE_USER', 'default') }}"
      password: "{{ env_var('CLICKHOUSE_PASSWORD', '') }}"
      custom_settings:
        # The dbt v2 ClickHouse adapter (beta) decompresses LZ4 only, while
        # ClickHouse 26.x compresses HTTP responses with ZSTD by default.
        network_compression_method: LZ4
```

### GA4

Try the GA4 package on Google's public sample
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset):
4.3 million events from November 2020 to January 2021. You need
[ClickHouse](https://clickhouse.com/docs/install), the
[gcloud CLI](https://cloud.google.com/sdk/docs/install),
[uv](https://docs.astral.sh/uv/), dbt v2 (`pip install dbt-oss`) and
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse) 0.10.1 or
later with its MCP server
(`pip install "dactopus-ossie-clickhouse[mcp] @ git+https://github.com/Dactopus/dactopus-ossie-clickhouse@v0.10.1"`).
Tested on ClickHouse 26.9.

1. **Export.** A Google Cloud project in the
   [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) is
   enough: no billing account, no Cloud Storage bucket. Save the script
   below as `export_ga4.py` and run:

   ```bash
   gcloud auth login
   gcloud projects create <project-id>
   gcloud services enable bigquery.googleapis.com --project <project-id>
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> data/ga4
   ```

   The script reads the daily tables with the BigQuery Storage Read API
   and writes one Parquet file per day (about 200 MB, 10 minutes). It
   passes the gcloud login token explicitly, so a
   `GOOGLE_APPLICATION_CREDENTIALS` set for another project does not get
   in the way:

   ```python
   import pathlib, subprocess, sys
   import pyarrow.parquet as pq
   from google.cloud import bigquery
   from google.oauth2.credentials import Credentials

   project, out = sys.argv[1], pathlib.Path(sys.argv[2])
   out.mkdir(parents=True, exist_ok=True)
   token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
   client = bigquery.Client(project=project, credentials=Credentials(token))
   dataset = "bigquery-public-data.ga4_obfuscated_sample_ecommerce"
   for table in client.list_tables(dataset):
       path = out / f"{table.table_id}.parquet"
       if not path.exists():
           rows = client.list_rows(client.get_table(table)).to_arrow(create_bqstorage_client=True)
           pq.write_table(rows, path, compression="zstd")
   ```

2. **Load** into the package's input table
   [`sources/ga4/input.sql`](sources/ga4/input.sql). It declares only the
   columns the package reads; any other way of delivering the export must
   fill the same table. Its database is a parameter, `ga4_raw` here; the
   package reads another one from the dbt variable `ga4_input_database`.

   ```bash
   clickhouse client --param_db=ga4_raw --multiquery < sources/ga4/input.sql
   clickhouse local --query "
     SELECT event_date, event_timestamp, event_name, event_params,
            user_pseudo_id, user_id,
            tuple(device.category) AS device, tuple(geo.country) AS geo,
            tuple(ecommerce.purchase_revenue, ecommerce.purchase_revenue_in_usd,
                  ecommerce.tax_value,
                  ecommerce.shipping_value, ecommerce.transaction_id) AS ecommerce
     FROM file('data/ga4/*.parquet') FORMAT Native" |
   clickhouse client --query "
     INSERT INTO ga4_raw.events (event_date, event_timestamp, event_name,
       event_params, user_pseudo_id, user_id, device, geo, ecommerce)
     FORMAT Native"
   ```

   The sample is older than the `session_traffic_source_last_click`
   column. Exports from October 2024 on have it with the
   `cross_channel_campaign` record the package reads: load it too, adding
   the column to the `INSERT` list and this expression to the `SELECT`.
   Without it the package falls back to the first source seen in a
   session, and revenue by source will not match the GA4 interface.

   ```sql
   tuple(tuple(session_traffic_source_last_click.cross_channel_campaign.source,
               session_traffic_source_last_click.cross_channel_campaign.medium,
               session_traffic_source_last_click.cross_channel_campaign.campaign_name))
     AS session_traffic_source_last_click
   ```

3. **Build** the canonical tables, with the profile of Quick start.

   ```bash
   dbt build --project-dir sources/ga4
   ```

4. **Validate** the model against the built tables. The model names its
   tables without a database: dactopus-ossie-clickhouse reads them in the database
   of its URL.

   ```bash
   dactopus-ossie-clickhouse validate entities/web_analytics.yaml --url http://user:password@host:8123/dactopus
   ```

5. **Ask.** Serve the model to an AI agent over MCP with
   `dactopus-ossie-clickhouse serve entities/web_analytics.yaml --url ...`, the
   same URL; its [README](https://github.com/Dactopus/dactopus-ossie-clickhouse#readme)
   shows how to connect an agent. Try sessions, conversion rate and
   revenue, by traffic source, device, country and date. The sample's
   dates are in UTC, the default, so the command takes no time zone; an
   export of your own property takes the property's (Use in your dbt
   project).

### Shopify

There is no public Shopify export, so try the package on the rows the
repository tests it with,
[`tests/shopify/fixture.sql`](tests/shopify/fixture.sql): twelve orders
of a shop in New York and its thirteen products, each a case the package
must get right (refunds, cancellations, discounts, tax included in
prices, a gift card, a tip, import duties, repeated deliveries, a
product's type and vendor changed, a deleted product). You need ClickHouse, dbt and
dactopus-ossie-clickhouse, as for GA4.

1. **Load** the package's input tables
   [`sources/shopify/input.sql`](sources/shopify/input.sql) and the rows.
   Their database is a parameter; the package reads it from the dbt
   variable `shopify_input_database` (default `shopify_raw`, kept here
   for your own store).

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
   asks 31 questions through dactopus-ossie-clickhouse, in the zone of
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

#### Your store

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
           legacyResourceId createdAt updatedAt note totalRefundedSet {MONEY}
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
               "id": rid, "order_id": oid, "created_at": ts(r["createdAt"]), "updated_at": refund_updated,
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

### WooCommerce

Try the package on the rows the repository tests it with,
[`tests/woocommerce/fixture.sql`](tests/woocommerce/fixture.sql): sixteen
orders and four refunds of a store in New York, as change data capture
(CDC) writes them, each a case the package must get right (refunds with
and without lines, a cancelled order, cash on delivery, fees, tax included
in prices, rows updated and then deleted, a deleted product, an order in
the trash, an order paid in EUR), with a catalog of seven products in
nested categories and with brands (a product in two categories, a
category moved under another, two categories of one name, a product in
the trash). You need ClickHouse, dbt and
dactopus-ossie-clickhouse, as for GA4. The package needs ClickHouse 26.7
or later: its models compute each shared subquery once
(`WITH ... AS MATERIALIZED`), which fails on earlier versions. CI runs it
on 26.7 and 26.9.

1. **Load** the package's input tables
   [`sources/woocommerce/input.sql`](sources/woocommerce/input.sql) and the
   rows. Their database is a parameter; the package reads it from the dbt
   variable `woocommerce_input_database` (default `woocommerce_raw`, kept
   here for your own store).

   ```bash
   clickhouse client --param_db=woocommerce_sample_raw --multiquery < sources/woocommerce/input.sql
   clickhouse client --param_db=woocommerce_sample_raw --multiquery < tests/woocommerce/fixture.sql
   ```

2. **Build** into a database of its own, in the store's time zone and
   with its currency. The tables hold neither: the time zone defaults to
   UTC, and without a currency the build stops.

   ```bash
   CLICKHOUSE_DATABASE=woocommerce_sample dbt build --project-dir sources/woocommerce \
       --vars '{woocommerce_input_database: woocommerce_sample_raw, woocommerce_timezone: America/New_York, woocommerce_currency: USD}'
   ```

3. **Validate** the model and **check** its answers: `check_numbers.py`
   asks 35 questions, in the zone of step 2, and compares the answers
   with numbers worked out by hand from the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/commerce.yaml --url http://user:password@host:8123/woocommerce_sample --time-zone America/New_York
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/woocommerce_sample OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York python3 tests/woocommerce/check_numbers.py
   ```

4. **Ask.** Serve `entities/commerce.yaml` in the zone of step 2, so
   that "today" in a question is the store's date. Try sales by month,
   orders awaiting payment, refunds by month and average order value, by
   shipping country and new or returning customer; sales by category,
   with and without its subcategories, and by brand.

   ```bash
   dactopus-ossie-clickhouse serve entities/commerce.yaml \
       --url http://user:password@host:8123/woocommerce_sample --time-zone America/New_York
   ```

#### Your store

The package reads the store's own order tables in ClickHouse, copied from
its MySQL database by CDC: every change of a row arrives as a new version
of it. This recipe was checked with open-source PeerDB 0.37 run from its
repository's Docker Compose setup
([PeerDB-io/peerdb](https://github.com/PeerDB-io/peerdb), tag `v0.37.11`),
over MySQL 8.4, on a local network without TLS. PeerDB stages the rows
for ClickHouse in S3; that setup runs MinIO for it. ClickPipes, ClickHouse
Cloud's CDC, runs PeerDB but is not checked yet.

1. **HPOS.** The tables are those of High-Performance Order Storage
   ([HPOS](https://developer.woocommerce.com/docs/features/high-performance-order-storage/)),
   WooCommerce 8.2 and later. WooCommerce turns it on for a new store
   unless a plugin is incompatible with it. A store on the legacy posts
   storage turns on compatibility mode on the Features page of the
   WooCommerce settings, which works with incompatible plugins too:
   WooCommerce then copies the store's history into the HPOS tables and
   keeps them in sync. A plugin that writes order data to `wp_postmeta`
   directly bypasses that sync, and WooCommerce does not notice. Run
   `wp wc hpos verify_data --re-migrate` regularly, daily for one, to find
   and fix those orders.

2. **MySQL.** CDC reads the binary log, which needs these server settings
   (`my.cnf`):

   ```ini
   [mysqld]
   binlog_format = ROW
   binlog_row_image = FULL
   binlog_row_metadata = FULL
   gtid_mode = ON
   enforce_gtid_consistency = ON
   ```

   and a user it reads with:

   ```sql
   CREATE USER 'peerdb'@'%' IDENTIFIED BY '<password>';
   GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'peerdb'@'%';
   ```

3. **Mirror** eleven tables into ClickHouse: the order tables, and the
   products and their categories and brands. Create the database
   (`CREATE DATABASE woocommerce_raw`); PeerDB creates the tables in it,
   with every column of the MySQL tables, of which
   [`input.sql`](sources/woocommerce/input.sql) lists those the package
   reads. In PeerDB's SQL interface (`psql` to its server, port 9900), with
   the WordPress database as `<wordpress>`:

   ```sql
   CREATE PEER woo_mysql FROM MYSQL WITH (
     host = '<mysql host>', port = 3306, user = 'peerdb', password = '<password>',
     database = '<wordpress>', flavor = 'mysql', replication_mechanism = 'gtid',
     disable_tls = true
   );
   CREATE PEER woo_ch FROM CLICKHOUSE WITH (
     host = '<clickhouse host>', port = 9000, user = '<user>', password = '<password>',
     database = 'woocommerce_raw', disable_tls = true
   );
   CREATE MIRROR woo_orders FROM woo_mysql TO woo_ch WITH TABLE MAPPING (
     <wordpress>.wp_wc_orders:wp_wc_orders,
     <wordpress>.wp_wc_order_addresses:wp_wc_order_addresses,
     <wordpress>.wp_wc_order_operational_data:wp_wc_order_operational_data,
     <wordpress>.wp_wc_orders_meta:wp_wc_orders_meta,
     <wordpress>.wp_woocommerce_order_items:wp_woocommerce_order_items,
     <wordpress>.wp_woocommerce_order_itemmeta:wp_woocommerce_order_itemmeta,
     <wordpress>.wp_wc_product_meta_lookup:wp_wc_product_meta_lookup
   ) WITH (do_initial_copy = true);
   CREATE MIRROR woo_terms FROM woo_mysql TO woo_ch WITH TABLE MAPPING (
     <wordpress>.wp_terms:wp_terms,
     <wordpress>.wp_term_taxonomy:wp_term_taxonomy,
     <wordpress>.wp_term_relationships:wp_term_relationships
   ) WITH (do_initial_copy = true);
   CREATE MIRROR woo_posts FROM woo_mysql TO woo_ch WITH TABLE MAPPING (
     {from: <wordpress>.wp_posts, to: wp_posts,
      exclude: [post_content, post_excerpt, post_content_filtered, to_ping, pinged, post_password]}
   ) WITH (do_initial_copy = true);
   ```

   Categories, brands and tags are terms (`wp_terms`) of a taxonomy
   (`wp_term_taxonomy`), linked to products in `wp_term_relationships`.
   `wp_posts` holds products and every page and revision of the site;
   its mirror leaves out the text columns, which the package does not
   read. A store whose order tables are mirrored already adds the other
   two mirrors as they are.

   Outside a local network, leave out `disable_tls` and give ClickHouse's
   secure port (9440 by default); that is not checked. The tables keep the
   store's prefix, `wp_` unless it chose another.
   PeerDB writes an empty MySQL value as the column type's default unless
   `PEERDB_NULLABLE` is on; the package reads both forms.

4. **Build** with the store's settings as variables, then validate and
   ask as above, with `woocommerce_timezone` as `--time-zone`, at the
   database the tables went to (`CLICKHOUSE_DATABASE`, default
   `dactopus`). The numbers match
   WooCommerce Analytics only while the date type and the excluded
   statuses repeat its settings.

   | Variable | Default | What it is |
   | --- | --- | --- |
   | `woocommerce_currency` | none, required | the store's currency (WooCommerce > Settings > General) |
   | `woocommerce_timezone` | `UTC` | the store's time zone (WordPress Settings > General) |
   | `woocommerce_date_type` | `date_paid` | Analytics' Date type: `date_paid`, `date_created` or `date_completed` (WooCommerce > Settings > Analytics) |
   | `woocommerce_excluded_statuses` | `[pending, cancelled, failed]` | Analytics' Excluded statuses, without the `wc-` prefix |
   | `woocommerce_order_statuses` | `{}` | statuses plugins add, each mapped to the core status it behaves as, such as `{shipped: completed}` |
   | `woocommerce_order_number_meta_key` | empty | the order meta key of a sequential order number plugin: `_order_number` for WebToffee's and SkyVerge's; empty, the number is the order id |
   | `woocommerce_price_decimals` | `2` | the store's price decimals, for amounts converted from another currency |
   | `woocommerce_table_prefix` | `wp_` | the tables' prefix; in a multisite, the site's, such as `wp_2_` |
   | `woocommerce_input_database` | `woocommerce_raw` | the database the mirror writes to |

   An order in a status that is neither core nor mapped fails the build,
   and so does an order in another currency without a rate the package
   knows (Known limits below).

5. **Next runs.** CDC keeps the input current; run `dbt build` again,
   and it is incremental. It rereads the orders with a row synced in the
   `woocommerce_lookback_days` (default 3) before the latest sync it has
   seen. `refunds` has no row for an order without refunds, so it keeps
   that sync in its table's comment, rewritten on each run; the dbt user
   needs `ALTER MODIFY COMMENT` on it (part of `ALTER TABLE`). `orders`
   keeps the orders a run rereads in `orders__changed` and drops it at
   the end; a run that fails leaves it, and the next run rereads its
   orders too.
   `dbt source freshness` warns when CDC has not synced
   an order for a day; a store without an order in a day warns too.

### Sensor.Community

[Sensor.Community](https://sensor.community/) is a citizen network of
air quality sensors: over 17,000 sensors reporting particulate matter,
temperature, humidity and pressure every few minutes, with the sensor
registry and the readings published as open data (Open Data Commons
[DbCL 1.0](https://opendatacommons.org/licenses/dbcl/1-0/), linked from
the site's footer). The package loads one country at a time; the
examples take Australia (`AU`), 36 sites and 66 sensors in October 2026.
You need ClickHouse, dbt, dactopus-ossie-clickhouse and
[uv](https://docs.astral.sh/uv/), as for GA4.

1. **Load** the package's input tables
   [`sources/sensor_community/input.sql`](sources/sensor_community/input.sql).
   Their database is a parameter; the package reads it from the dbt
   variable `sensor_community_input_database` (default
   `sensor_community_raw`).

   ```bash
   clickhouse client --param_db=sensor_community_raw --multiquery < sources/sensor_community/input.sql
   ```

2. **Snapshot** the sensors of the country. The API returns every
   sensor that reported in the last five minutes, with its site's
   coordinates, country and whether it is indoors; nothing else carries
   the country, so the snapshot is the registry, and a sensor appears in
   it once it has reported during a snapshot. ClickHouse reads the API
   itself. The API asks every client for a `User-Agent` that names a
   contact ([the project's wiki](https://github.com/opendata-stuttgart/meta/wiki/APIs));
   put yours in place of the one below.

   ```sql
   INSERT INTO sensor_community_raw.locations (location_id, sensor_id, sensor_type, latitude, longitude, altitude,
       country, indoor, reported_at, snapshot_at)
   SELECT location.id, sensor.id, argMax(sensor.sensor_type.name, t),
          argMax(toFloat64(location.latitude), t), argMax(toFloat64(location.longitude), t),
          argMax(toFloat64OrNull(location.altitude), t), argMax(location.country, t), argMax(location.indoor = 1, t),
          max(t), now('UTC')
   FROM
   (
       SELECT *, parseDateTimeBestEffort(timestamp, 'UTC') AS t
       FROM url('https://data.sensor.community/airrohr/v1/filter/country=AU',
                headers('User-Agent' = 'dactopus-data-models loader (https://github.com/Dactopus)'), JSONEachRow,
                'location Tuple(id UInt32, country String, indoor UInt8, latitude String, longitude String, altitude Nullable(String)),
                 sensor Tuple(id UInt32, sensor_type Tuple(id UInt32, name String, manufacturer String)), timestamp String')
   )
   GROUP BY location.id, sensor.id
   ```

   Run it every five minutes (cron, or anything that runs a query on a
   schedule): each run appends the snapshot, one row per sensor with its
   latest record (the API gives a sensor several in five minutes), and
   the package reads the latest row of each site. A snapshot is visible
   to the model as soon as it is loaded, with no build: it gives each
   site's last contact (`devices.last_contact_at`), country and indoor
   flag. The table
   keeps only each sensor's latest snapshot once ClickHouse merges it
   (`input.sql`), so it stays as large as the country's sensors; the
   history of the snapshots is not kept. The snapshots are also what
   tells a sensor that has gone quiet from one that never existed. Several countries go in one query
   (`country=AU,NZ`); the whole network is
   `https://data.sensor.community/static/v2/data.json`, 17,500 rows.

3. **Load the history.** The archive publishes one CSV file per sensor
   and day, all of a day at once the night after: between 03:20 and
   06:00 UTC on every day of 2026 but one, which ended at 08:45. A
   published file does not change. Save the script below as
   `load_sensor_community.py` and run it with the ClickHouse HTTP URL,
   the input database, the country and the first and last day to load:

   ```bash
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU 2025-10-20 2026-10-19
   ```

   It takes the country's sensors from the snapshots, fetches each
   sensor's file for each day (four at a time; an indoor sensor's file
   has the suffix `_indoor`, earlier years are gzipped), and inserts a
   day at a time: about 20 seconds per day of Australia, two hours for
   a year. It loads a day only from 10:00 UTC of the day after, when
   the archive has published it whole, and stops before a later one. A
   sensor without a file for a day has no readings that day; some
   sensors the API lists have no file at all (in Australia, the two of
   site 30186, from September 20 to October 19, 2026). A sensor that
   stopped reporting before the first snapshot is not in the snapshots
   and is not loaded, so a year back holds fewer sensors than the
   archive. The archive's own count of sensors per country and day
   (`sensors_per_country_per_day.json` at its root) runs higher: for
   Australia from September 20 to October 19, 2026, by one PMS5003 and
   one BME280 every day from September 23, and by one SDS011, one or two
   DHT22, or both, on 23 of the 30 days. Every sensor with files in the
   snapshots behind that load, taken on October 21, is loaded; the
   archive does not say which sensors its count includes. Sensors of
   other types than SDS011, PMS5003, BME280 and DHT22 are left out: the
   package does not read them. Values load as the files have them. Some
   firmware sends the pressure in hPa instead of Pa (a BME280 in
   Australia); the package reads a pressure from 300 to 1,100 as hPa and
   converts it to Pa (`input.sql`). The script sends the `User-Agent` from
   `SENSOR_COMMUNITY_AGENT`, or the one shown above; set it to yours.
   It connects to ClickHouse as `CLICKHOUSE_USER` (default `default`)
   with `CLICKHOUSE_PASSWORD`. It needs
   [uv](https://docs.astral.sh/uv/) for the one package it uses,
   `certifi`: Python from python.org on macOS does not see the system's
   root certificates.

   <details><summary>load_sensor_community.py</summary>

   ```python
   import concurrent.futures, csv, datetime, gzip, http.client, io, os, ssl, sys, time, urllib.error, urllib.parse, urllib.request
   import certifi

   url, db, country, since, until = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
   AGENT = os.environ.get("SENSOR_COMMUNITY_AGENT", "dactopus-data-models loader (https://github.com/Dactopus)")
   ARCHIVE = "https://archive.sensor.community"
   TLS = ssl.create_default_context(cafile=certifi.where())
   LOGIN = {"X-ClickHouse-User": os.environ.get("CLICKHOUSE_USER", "default"),
            "X-ClickHouse-Key": os.environ.get("CLICKHOUSE_PASSWORD", "")}
   NOW = datetime.datetime.now(datetime.timezone.utc)
   THIS_YEAR = str(NOW.year)
   # The archive publishes a day the night after, done by 10:00 UTC; the
   # last day it has whole.
   PUBLISHED = (NOW - datetime.timedelta(hours=10)).date() - datetime.timedelta(days=1)
   TYPES = {"SDS011": "sds011", "PMS5003": "pms5003", "BME280": "bme280", "DHT22": "dht22"}
   COLUMNS = ["sensor_id", "sensor_type", "location", "lat", "lon", "timestamp",
              "P1", "P2", "temperature", "humidity", "pressure"]


   def query(sql, body=None, **settings):
       req = urllib.request.Request(url + "/?" + urllib.parse.urlencode({"query": sql, **settings}), body, LOGIN)
       try:
           return urllib.request.urlopen(req, context=TLS).read().decode()
       except urllib.error.HTTPError as e:
           sys.exit(e.read().decode())


   def get(path):
       """The file's bytes, None when the archive has no such file."""
       for attempt in range(5):
           try:
               with urllib.request.urlopen(urllib.request.Request(path, headers={"User-Agent": AGENT}), context=TLS, timeout=60) as r:
                   return r.read()
           except urllib.error.HTTPError as e:
               if e.code == 404:
                   return None
               if e.code < 500 and e.code != 429:
                   raise
           except (OSError, http.client.HTTPException):  # timeouts and resets, while reading too
               pass
           time.sleep(2 ** attempt)  # the archive drops a connection now and then
       sys.exit(f"gave up on {path}")


   def fetch(day, kind, sensor, indoor):
       # An indoor sensor's file has the suffix _indoor; a sensor that moved
       # may have either, so both names are tried, the flagged one first.
       for suffix in (("_indoor", "") if indoor else ("", "_indoor")):
           name = f"{day}_{kind}_sensor_{sensor}{suffix}.csv"
           paths = (f"{ARCHIVE}/{day}/{name}", f"{ARCHIVE}/{day[:4]}/{day}/{name}.gz")
           # Earlier years are in their year's folder; the current one's
           # files are in the root until the archive moves them.
           for path in (paths if day[:4] == THIS_YEAR else paths[::-1]):
               data = get(path)
               if data is not None:
                   return gzip.decompress(data) if path.endswith(".gz") else data
       return None


   sensors = [(TYPES[t], s, i == "true") for s, t, i in csv.reader(io.StringIO(query(
       f"SELECT sensor_id, sensor_type, argMax(indoor, snapshot_at) FROM {db}.locations WHERE country = {{country:String}} "
       f"AND sensor_type IN ({', '.join(repr(t) for t in TYPES)}) GROUP BY sensor_id, sensor_type FORMAT CSV",
       param_country=country)))]
   if not sensors:
       sys.exit(f"no sensors of {country} in {db}.locations: take a snapshot first")
   if not since:
       sys.exit(f"no readings of {country} in {db}.readings: load the history first")
   pool = concurrent.futures.ThreadPoolExecutor(4)
   day, last = datetime.date.fromisoformat(since), datetime.date.fromisoformat(until)
   if last > PUBLISHED:
       print(f"the archive may still be publishing the days after {PUBLISHED}: loading to {PUBLISHED}", flush=True)
       last = PUBLISHED
   while day <= last:
       out = io.StringIO()
       writer = csv.DictWriter(out, COLUMNS, delimiter=";", extrasaction="ignore", restval="")
       writer.writeheader()
       files = 0
       for data in pool.map(lambda ks: fetch(day.isoformat(), *ks), sensors):
           if data:
               files += 1
               writer.writerows(csv.DictReader(io.StringIO(data.decode()), delimiter=";"))
       if files:
           # Some firmware writes the word unknown for a measure it could not
           # take; it becomes NULL.
           query(f"INSERT INTO {db}.readings FORMAT CSVWithNames", out.getvalue().encode(),
                 format_csv_delimiter=";", input_format_csv_use_default_on_bad_values=1)
       print(day, files, "files of", len(sensors), "sensors", flush=True)
       day += datetime.timedelta(days=1)
   ```

   </details>

4. **Build** `readings`, `devices_archive` and the view `devices` into
   the target database (`CLICKHOUSE_DATABASE`, default `dactopus`), with
   the profile of Quick start. Every time and date is UTC, so there is
   no time zone to set.

   ```bash
   dbt build --project-dir sources/sensor_community
   ```

5. **Validate** the model against the built tables, and **check** the
   package's answers: `check_numbers.py` asks 17 questions over the
   hand-written rows of
   [`tests/sensor_community/fixture.sql`](tests/sensor_community/fixture.sql),
   built into databases of their own, and compares the answers with
   numbers worked out by hand from the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/iot.yaml --url http://user:password@host:8123/dactopus
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < sources/sensor_community/input.sql
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < tests/sensor_community/fixture.sql
   CLICKHOUSE_DATABASE=sensor_community_sample dbt build --project-dir sources/sensor_community \
       --vars '{sensor_community_input_database: sensor_community_sample_raw}'
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/sensor_community_sample python3 tests/sensor_community/check_numbers.py
   ```

6. **Ask.** Serve `entities/iot.yaml` with `dactopus-ossie-clickhouse serve`
   at the database of step 4. Try the average temperature at each site
   over the last week, the devices silent for more than an hour, PM2.5
   by day, and how many devices reported yesterday. The archive
   publishes a day the night after, so the latest reading is hours old;
   the model tells agents to measure silence from the latest contact in
   the data, which the snapshots keep within minutes of now, and to name
   that time and its age.

7. **Next loads.** Once a day after 10:00 UTC, load from the day after
   the country's last day loaded to yesterday, keep the snapshots
   running, and build again. The build is incremental for `readings`;
   `devices_archive`, one row per site, is rebuilt whole and reads every
   reading, so its time grows with the history: 0.05 seconds on a laptop
   for a month of Australia, 2.3 million readings. The snapshots need no
   build. Each day is loaded once.
   Loading a day twice by hand is harmless: the package reads each
   reading once.

   ```bash
   since=$(clickhouse client --query "SELECT max(toDate(timestamp)) + 1 FROM sensor_community_raw.readings
       WHERE sensor_id IN (SELECT sensor_id FROM sensor_community_raw.locations WHERE country = 'AU') HAVING count() > 0")
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU "$since" "$(date -u -v-1d +%F)"
   ```

   On Linux, yesterday is `$(date -u -d yesterday +%F)`.

## What the GA4 model answers

[`entities/web_analytics.yaml`](entities/web_analytics.yaml) has 12
metrics, each on the dataset whose rows it counts; a question names one
as `dataset.metric` (`sessions.session_count`):

- sessions: `session_count`, `engaged_sessions`, `engagement_rate`,
  `users`, `session_conversion_rate`, `user_conversion_rate`,
  `page_view_count`. They break down by the session's date, week and
  month; traffic source, medium and campaign; landing page, device and
  country.
- purchases: `purchase_count`, `gross_purchase_revenue`,
  `gross_purchase_revenue_usd`, `average_gross_purchase_revenue`. They
  break down by the session fields above, and by the purchase's own
  date, week, month and currency.
- events: `event_count`. It breaks down by the session fields above, and
  by the event's own date, name, page, device and country.

The descriptions in the file say what each one counts.

## Known differences from the GA4 interface

Numbers from the model and from the GA4 interface can differ for reasons
the model states in its descriptions:

- **Sessions and users** are counted exactly; the GA4 interface estimates
  them, so they differ slightly. A user is a browser on a device
  (`user_pseudo_id`), not a person.
- **Traffic source** matches the interface (last non-direct click) only
  for exports from October 2024 on, loaded with the
  `session_traffic_source_last_click` column. Older exports fall back to
  the first source seen in the session.
- **Purchases** are what the site sent to GA4, not the store's orders:
  purchases made with tracking blocked are missing. A purchase sent twice
  by the same user with the same transaction id counts once, as in GA4.
- **Revenue** is in the currency of each purchase. A store that sells in
  several currencies has to read it by `purchases.currency`;
  `purchases.gross_purchase_revenue_usd` is converted by Google at a
  rate it does not document.
- **Refunds** are not subtracted: the model reads purchase events only.
  The metrics are GA4's gross purchase revenue; the interface's
  "Purchase revenue" subtracts the refunds the site sent to GA4, so it
  is lower when there were any ([GA4 metrics](https://support.google.com/analytics/answer/9143382)).
- **Dates** are in the GA4 property's time zone; a session that crosses
  midnight counts once, on the day it started. "Today" is the
  property's date when the model is served in that zone (Use in your dbt
  project). Properties outside UTC
  are not tested yet ([#1](https://github.com/Dactopus/dactopus-data-models/issues/1)).

## What the commerce model answers

[`entities/commerce.yaml`](entities/commerce.yaml) has 35 metrics. A
metric that counts the rows of one dataset is on that dataset, and a
question names it as `dataset.metric` (`orders.revenue`). The 18 that
read order lines, their categories and brands, or refunds together with
`orders.in_sales_reports` are on the model and go by their name alone:

- orders: `order_count`, `all_orders`, `all_orders_total`, `revenue`,
  `refunded_amount`, `refund_rate`, `average_order_value`,
  `items_per_order`, `discount_amount`, `shipping_amount`, `tax_amount`,
  `customers`, `repeat_order_share`. They break down by the order's
  date, week and month; payment and fulfillment status, cancelled or
  not, counted in the store's reports or not, channel and currency;
  shipping country, region and city; new or repeat customer.
- order lines (on the model): `items_sold`, `items_net`, `line_revenue`,
  `items_returned`, `line_returned_amount`, `line_net_revenue`. They
  break down by product, variant, SKU and title, and by the order fields
  above. Returns count on the date of the order.
- categories (on the model): `category_items_sold`, `category_revenue`,
  `category_items_returned`, `category_returned_amount`,
  `category_net_revenue`. They break down by `line_categories.category`
  and `category_path`, and by the order fields above.
- brands (on the model): `brand_items_sold`, `brand_revenue`,
  `brand_items_returned`, `brand_returned_amount`, `brand_net_revenue`.
  They break down by `line_brands.brand` and by the order fields above.
- refunds (on the model): `refund_count`, `refunds_total`. They break
  down by the refund's own date, week and month, and by the order fields
  above.
- sales events: `net_revenue`. It breaks down by the event's date, week,
  month and kind (an order, a refund, a cancellation), and by the order
  fields above.
- the catalog: `products.product_count`, by status (active, draft,
  archived), title and the date of the last sale;
  `product_categories.product_count` by category and
  `product_brands.product_count` by brand.

A category is the product type at Shopify and a product category at
WooCommerce, where categories nest; a brand is the vendor at Shopify and
a product brand at WooCommerce. Both are the product's current ones: a
product moved to another category takes its past sales with it, as in
the stores' reports. A line counts in every category and brand of its
product, so they overlap and never add up to a total. The category
metrics count a line in its product's own categories, as WooCommerce
Analytics' Categories report does; one category with its subcategories
is the order lines' metrics filtered by `line_categories.category_path`.
Collections and tags are not modelled.

The numbers follow the store's own sales reports: every metric but
`orders.all_orders` and `orders.all_orders_total` counts only the orders
those reports count (`orders.in_sales_reports`). Shopify's reports count
every order; WooCommerce's, by default, paid orders that are not
cancelled or failed.

"Sales" or "revenue" without a qualifier is `sales_events.net_revenue`:
orders less refunds and cancellations, with shipping and tax. By
`sales_events.event_month` it gives each month's sales as the store's
reports show them, a refund or a cancellation in the month it was made;
by `orders.order_month`, what each month's orders earned, later refunds
included. `orders.revenue` is orders as placed. Amounts are in the
store's currency.

Dates are in the store's time zone, and so is "today" (`CURRENT_DATE`)
when the model is served in that zone (Use in your dbt project).

## Known differences from Shopify's reports

On the development store the package was checked against,
`sales_events.net_revenue` equals Shopify's total sales overall, by
shipping country and by new or returning customer, and, by
`sales_events.event_date`, for each order on each day;
`orders.average_order_value` equals the store's. Units, goods revenue,
returns and net sales by product type and by vendor equal the reports'
over all time and by month, and the counts of products by status, type
and vendor equal the admin's. Test orders are left out, as in the
reports. Other numbers differ by definition, and the model's
descriptions say how:

- **Gross and net sales** in Shopify's reports are goods only.
  `orders.revenue` and `sales_events.net_revenue` add shipping, tax and
  import duties; `line_revenue` is goods after discounts.
- **Sales reversals** (formerly returns) in the reports are without tax
  and count a cancelled unpaid order as reversed.
  `orders.refunded_amount` is the money paid back, with its tax; a
  cancelled unpaid order has nothing refunded.
  `sales_events.net_revenue` takes a cancelled order back on the day it
  was cancelled, as the reports do, through a cancellation event.
- **Taxes** in the reports are net of refunded tax; `orders.tax_amount`
  is the tax on the order as placed.
- **New or returning**: the reports keep a cancelled order in its
  customer's sequence (a cancelled first order shows as new). The model
  gives a cancelled order no place in the sequence, so a customer's
  first order after a cancelled one is new.
- **Discounts** can differ on an order created through the API with its
  tax lines set on the price before the discount (10.00 against the
  report's 8.84 on the development store); on orders from the storefront
  they match.
- **A refunded tip** has no refund line, so it cannot be told from a
  refund of goods and counts as a refund
  ([#6](https://github.com/Dactopus/dactopus-data-models/issues/6)).
  Tips and gift cards sold are otherwise not sales, as in the reports.
- **Gift cards** count in the reports' units sold and returned; here a
  gift card is no product, so `items_sold` and `items_returned` leave it
  out.
- **Returns by product, type or vendor**: the reports date a return on
  the day of the refund, `items_returned` and `line_returned_amount` on
  the day of the order. Over all time they are equal.
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

The memory a build needs grows with the shop's history, slowly. On
synthetic shops of 2, 4 and 8 million orders (2.5 lines per order, 30%
of orders changed once; ClickHouse 26.9), the largest query of the first
build, `orders`, peaked at 1.1, 1.5 and 2.0 GB, and an incremental run
of it at 0.21 and 0.26 GB for 2 and 4 million; the structural test
`orders_amounts_consistent` peaked at 0.7, 1.7 and 2.7 GB, so on a
server that allows a query 3 GB it is the first to fail, past 8 million
orders ([#8](https://github.com/Dactopus/dactopus-data-models/issues/8)).
The input tables' sorting keys (`input.sql`) are part of this: with
other keys the package builds the same tables, sorting each whole in
memory.

## Known differences from WooCommerce Analytics

On a local test store (WooCommerce 11.2.1) the package was checked
against Analytics under each of its three date types, other settings as
WooCommerce ships them. Every order's total, subtotal, tax, shipping,
items, refunds, report date and whether the reports count it matched.
`sales_events.net_revenue` by `sales_events.event_month` equals the
reports' total sales for every month, and `orders.order_count`,
`orders.average_order_value`, `orders.items_per_order`,
`orders.discount_amount`, `items_net`, refunds by month and new or
returning registered customers equal the reports' numbers.
`orders.average_order_value` filtered by a category equals the Orders
report filtered by it, subcategories included. After a refund, a deleted
order and a new one, an incremental run matched a full rebuild and the
reports again. Other numbers differ by definition, and the model's
descriptions say how:

- **Net sales** in the reports are goods after refunds, without shipping
  and tax. `sales_events.net_revenue` is the reports' total sales;
  `line_revenue` is goods after discounts, before refunds.
- **Shipping and tax** in the reports are net of what was refunded, in
  the month of the refund; `orders.shipping_amount` and
  `orders.tax_amount` are as on the order.
- **New or returning**: the reports count a guest as a customer by email.
  The model gives guest orders no place in a customer's sequence, as at
  Shopify; registered customers match.
- **SKU**: WooCommerce keeps none on the order, so `order_lines.sku` is
  the product's current SKU, and empty once the product is deleted.
- **Test orders** are not marked in WooCommerce and count as orders.
- **Fulfillment**: WooCommerce (11.2) keeps no shipments of its own by
  default; a completed order is fulfilled and any other unfulfilled.
- **Categories and products**: the Categories and Products reports also
  count orders on hold that are not paid yet, which the Revenue and
  Orders reports and the model leave out under the default date type.
  Without them, units, revenue and returns by category and product equal
  the reports'. A parent category with no products of its own has no row
  in the Categories report and a row of 0 here. Analytics has no report
  by brand.

Known limits of the package: an order a multi-currency plugin placed in
another currency is converted to the store's as WooPayments and FOX
convert it for Analytics, from the rates they keep with the order. Other
plugins' orders, and FOX orders without that rate, have no rate the
package knows and fail the build; a FOX refund without its own rate is
converted at its order's, where FOX takes the rate of its settings at
the time. In a store whose prices include tax, line
totals are not rounded, so the lines add up to the subtotal within a
cent. CDC syncs each table apart, so a run can see an order before its
lines: the check that lines add up to the subtotal only warns, and the
next run completes the order. A store in compatibility mode can drift
from its legacy storage between runs of `wp wc hpos verify_data
--re-migrate` (Your store, step 1).

## What the iot model answers

[`entities/iot.yaml`](entities/iot.yaml) has 9 metrics, each on the
dataset whose rows it counts; a question names one as `dataset.metric`
(`devices.device_count`):

- readings: `reading_count`, `avg_value`, `min_value`, `max_value`,
  `reporting_devices`, `last_reading_time`. They break down by measure
  (`pm10`, `pm2_5`, `temperature`, `humidity`, `pressure`); the
  reading's hour, date, week and month; device, sensor and sensor type;
  and by the device fields below.
- devices: `device_count`, `last_contact_time`,
  `minutes_since_last_contact`. They break down by country, indoor or
  not, the sensor types a site has, its first and latest reading, and its
  last contact: the later of its latest report in the snapshots and its
  latest reading.

A device is a site: one place with coordinates, where a board reports
through one or more sensors. A value metric means something for one
measure at a time, so the model tells agents to filter or break down by
`readings.measure` and never to average different measures together.
Units: PM10 and PM2.5 in µg/m³, temperature in °C, relative humidity in
%, pressure in Pa.

## Limits of the iot model

- **Time.** Every time is UTC, and a reading's date is its date in UTC.
  The source gives a site no time zone, and Australia alone has three,
  so a reading near local midnight falls on another date.
- **Values** are as the sensors sent them, not cleaned: humidity of 100
  in dew, dust peaks in rain and a faulty sensor's readings stay (a site
  in Australia averaged 129.9 °C over a week). The package corrects two
  things only: `nan` is no reading, and a pressure from 300 to 1,100 is
  read as hPa and converted to Pa.
- **Silence** is measured from the latest contact in the data
  (`devices.last_contact_time`), not from the clock: "silent for more
  than an hour" is an hour before it, and the agent names it and its
  age. While the snapshots run it is within minutes of now; without them
  it is the latest reading, hours old, since the archive publishes a day
  the day after. The snapshots keep no history, so the answer is exact
  only if they ran without a gap through the hour before that time.
- **Snapshots loaded by 0.5.0's query** took several records per
  sensor, and ClickHouse kept the last of them on insert, in the API's
  order, which may not be the latest. A sensor silent since then can
  show a last contact up to five minutes early. The query of step 2
  keeps each sensor's latest record.
- **Indoor sites** count in every average across devices; the model
  tells agents to say so and to offer the outdoor ones
  (`devices.is_indoor`). A site that was never in a snapshot has no
  country and no indoor flag.
- **Devices by their readings.** `devices.device_count` filtered on a
  field of `readings` (`readings.reading_date = '2026-10-19'`) counts
  each site with at least one such reading, as
  `readings.reporting_devices` does. Sites without a reading on a date
  cannot be counted: `NOT` in that filter keeps every site with a
  reading on another date
  ([dactopus-ossie-clickhouse#10](https://github.com/Dactopus/dactopus-ossie-clickhouse/issues/10)).
  Sites silent since a time are found through `devices.last_contact_at`.
- **Sensor types**: SDS011, PMS5003, BME280 and DHT22. Readings of other
  types, noise meters among them, are left out.
- **`devices_archive`**, behind the view `devices`, is rebuilt whole on
  every run (Quick start, step 7).

## Use in your dbt project

Add the packages you need to your project's `packages.yml`, pinned to a
release tag: GA4 and your store's package, here Shopify (for
WooCommerce, `subdirectory: sources/woocommerce`; for Sensor.Community,
`sources/sensor_community`):

```yaml
packages:
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.6.1
    subdirectory: sources/ga4
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.6.1
    subdirectory: sources/shopify
```

The Shopify and WooCommerce packages write the same tables, so a project
installs one of them: with both, dbt stops before building anything. A
business with a store on each builds them into separate target
databases, as for several stores below.

The GA4 package writes `events`, `sessions` and `purchases` to your
target's database and reads its input from `ga4_raw.events`. The Shopify
package writes `orders`, `order_lines`, `refunds`, `sales_events`, the
catalog's `products` and the tables of categories and brands, and reads
its input from the five tables in `shopify_raw`; the WooCommerce package
writes the same tables from the eleven in `woocommerce_raw`. The
Sensor.Community package writes `readings`, `devices_archive` and the
view `devices` from `locations` and `readings` in
`sensor_community_raw`. Name
other databases, and set the store's time zone: without it, every date
is in UTC and orders near midnight fall on the wrong day. WooCommerce
also needs the store's currency, and its report settings where they
differ from WooCommerce's (Your store, step 4). The WooCommerce package
needs ClickHouse 26.7 or later, and its dbt user needs
`ALTER MODIFY COMMENT` on `refunds` (Your store, step 5).

```yaml
vars:
  dactopus_ga4:
    ga4_input_database: my_ga4_export
  dactopus_shopify:
    shopify_input_database: my_shopify_export
    shopify_timezone: Europe/Berlin
  dactopus_woocommerce:
    woocommerce_input_database: my_woocommerce_cdc
    woocommerce_timezone: Europe/Berlin
    woocommerce_currency: EUR
  dactopus_sensor_community:
    sensor_community_input_database: my_sensor_community
```

`shopify_lookback_days`, `woocommerce_lookback_days` and
`sensor_community_lookback_days` (default 3) are how far before its last
load or sync an incremental run rereads the input, for inserts that
commit late.

Each package's `deployment.yml` lists what a deployment sets and reads:
the Ossie model its tables serve, the variables above by their role
(input database, time zone) and the tables a deployment counts rows per
day in, with the Date column it counts by and the time column that date
is the day of. A tool that deploys the packages reads it in place of
this section. A change of `shopify_timezone` or `woocommerce_timezone`
needs `dbt build --full-refresh`: an incremental run rebuilds only the
orders and refunds loaded since the last one, the rest keep the days of
the old zone, and no dbt test fails. `uv run tests/check_deployment.py
sources/shopify --time-zone <zone>` counts the rows whose date is not
the day of their time in the zone: none in a table built whole in it.

Point dactopus-ossie-clickhouse at your target's database
(`--url http://host:8123/<database>`, or `https://` over TLS) and take
the Ossie models from the same tag. On dbt v2 with ClickHouse 26.x, set
`custom_settings: {network_compression_method: LZ4}` in your profile, as
the profile of [Quick start](#quick-start) does: the v2
ClickHouse adapter (beta) cannot read ClickHouse's default ZSTD
responses.

Serve the commerce and GA4 models in the time zone their dates were
built in: `--time-zone` with the value of `shopify_timezone` or
`woocommerce_timezone`, and for GA4 the property's time zone, in which
the export writes `event_date` ([export
schema](https://support.google.com/analytics/answer/7029846)). "Today"
(`CURRENT_DATE`) is then the date there, and so is a time written
without an offset, as a plain string (`'2026-10-01 09:00:00'`) or a
literal (`TIMESTAMP '2026-10-01 09:00:00'`); times in answers carry
their offset from UTC. Keep
the two values the same: a store in New York built with
`America/New_York` and served in UTC finds no orders of today after
20:00 (19:00 in winter), when the date in UTC is already tomorrow. The
iot model's dates are in UTC, the default, so it takes no zone.
`OSSIE_CLICKHOUSE_TIME_ZONE` sets the zone for every model served from
that environment, the iot model included; give the option to each model
instead.

```bash
dactopus-ossie-clickhouse serve entities/commerce.yaml --url http://host:8123/<database> --time-zone Europe/Berlin
```

A store with GA4 and a store package built into one database serves both
models to one agent as one model. One `--time-zone` covers both, so
build the store package in the GA4 property's zone; otherwise "today"
is another date in one of them:

```bash
dactopus-ossie-clickhouse serve entities/web_analytics.yaml entities/commerce.yaml --url http://host:8123/<database> --time-zone Europe/Berlin
```

There "sales", "revenue", "orders" and "average order value" are the
store's figures from the commerce model; the GA4 metrics are named after
GA4's own (`purchases.gross_purchase_revenue`), and the agent names both
when asked to compare them.

On dbt v2, `dbt source freshness` fails on ClickHouse for every source
([dbt-labs/dbt#16714](https://github.com/dbt-labs/dbt/issues/16714)).
Each package carries macros that fix it; dbt uses a package's macro in
place of its own only when your `dbt_project.yml` lists the package
after your project's name (`my_project` here):

```yaml
dispatch:
  - macro_namespace: dbt
    search_order: [my_project, dactopus_ga4, dactopus_shopify, dactopus_woocommerce, dactopus_sensor_community, dbt]
```

Freshness then reports the same ages as on dbt v1.

Several GA4 properties: each exports to its own BigQuery dataset. Build
the package once per property, each with its own input and target
database, and serve the model once per target. A total across properties
is not modelled. The same holds for several Shopify or WooCommerce
stores, and for the sites of a WordPress multisite, each with its own
table prefix.

## Layout

    entities/<domain>.yaml    one Ossie model per domain (web_analytics, commerce, iot)
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      deployment.yml          what a deployment sets and reads: the Ossie
                              model, the dbt variables, the tables counted
                              per day
      macros/                 SQL the package's models share
      models/                 one model per entity, named after it
      models/schema.yml       structural checks (dbt tests)
      tests/                  checks that need their own SQL
    tests/<source>/           hand-written input rows and the numbers the
                              model must answer over them
    tests/profiles.yml        the dbt profile CI builds with; a package
                              ships none
    docs/                     the diagram above and its interactive page

A package's model writes the entity's table, named after it, in the
database the deployment chooses. The entity's dataset in the domain's
Ossie model names that table without a database (an Ossie model is one
file, since relationships and metrics span entities), so one model serves
any database dactopus-ossie-clickhouse connects to, and
`dactopus-ossie-clickhouse validate --url` checks that the package delivers every
column the entity declares. A deployment picks one package per entity.

This is one repository, not one per source. Packages map onto shared
entities, so they are released together with them under a single version.
Consumers take the subdirectories they need.

## What a source package is

A package is more than a table schema. Every entity–source pair has six
parts:

| Part | Lives in | Example |
| --- | --- | --- |
| 1. Schema: row grain, keys | entity | one row per order |
| 2. Mapping from the source | package | where `refunded_total` comes from, how statuses map, what happens to currency |
| 3. Refresh strategy | package | by load time or a re-read window; the latest version of each row |
| 4. Structural checks | package | uniqueness, not-null, freshness, `refunded_total <= total` |
| 5. Field descriptions | entity | plus `ai_context` and synonyms |
| 6. Simple metrics | entity | net revenue = `total - refunded_total` |

Part 2 is where the value is. Sources differ in what a status means,
when a refund counts and when the same thing is sent twice: GA4, for one,
sends a purchase again when the thank-you page is reloaded. A package
that gets the schema right and the mapping wrong returns wrong numbers
that look plausible.

## Out of scope

- Loading data. This README gives recipes; the tools are someone else's.
- Running queries. That is dactopus-ossie-clickhouse.
- Reconciling with the source's own reports through its API.
- Anything that needs two sources at once: attributing sessions to
  orders, matching customers across systems, cross-source marts.
- API connectors (for example to the GA4 API) and Universal Analytics.

Everything here is Apache 2.0. If a file cannot be released under it, it
does not belong here.

## Authoring rules

**Format.** Ossie schema `0.2.0.dev0`, the only version the upstream
schema accepts today. Write expressions in `ANSI_SQL`; dactopus-ossie-clickhouse
also accepts `OSSIE_SQL_2026`. Mapping, refresh and checks live in the
package's dbt project, not in the Ossie files, so entities stay plain Ossie
that any Ossie tool reads. The only extension used is dactopus-ossie-clickhouse's
`CLICKHOUSE` namespace and its `dedup` key.

**The canon is selected, not designed.** A field that at least two
sources provide goes into the canonical entity. While a domain has a
single source (GA4 for events), a field qualifies when its meaning does
not depend on that source. Where the second source is known but not yet
packaged, the field must exist there too, checked against its
documentation. A field only one source has is not modelled until a
second source needs it. A reference domain (`iot`) is built from one
public dataset with no second source planned: a field qualifies when any
network of devices would have it with the same meaning.

**Descriptions are part of the model.** Agents answer from descriptions,
synonyms and `ai_context`. Without them even strong models guess. A dbt
`.yml` description is the minimum, not the target.

**Name the "obvious" choices.** Models break on what looks obvious:
- Order date: placed, paid or shipped? Store time zone or UTC?
- Customer: account, email or card?

A package states which one it uses and why.

**dactopus-ossie-clickhouse limits are rules here.**
- Joins are many-to-one only, on a declared primary or unique key, and
  each dataset has one path from the question's root.
- Two fact tables meet only on shared dimensions: their metrics in one
  question are computed apart and merged. A metric that combines both
  facts needs them in one table, so such a mart is materialized as one
  fact table.
- A metric cannot reference another metric by name; repeat the
  expression.
- No time grain or derived dimensions: declare one field per grain.
- `source` is a table name without a database, not a query: the
  deployment picks the database.

See its [model authoring guide](https://github.com/Dactopus/dactopus-ossie-clickhouse/blob/main/docs/model-authoring.md).

**Access control is not modelled.** It comes from ClickHouse grants.

## Versioning

One version for the whole repository, [SemVer](https://semver.org), tags
`vX.Y.Z`. The Ossie schema version (`0.2.0.dev0`) is separate: the model
files carry it, and the changelog names it for every release.

A breaking change is anything that stops a deployment working or changes
its numbers: renaming or removing a field, metric or column; changing what
a metric means (the same columns, different numbers); a new required
column in a package's input. Before 1.0 such changes come in a minor
release, after 1.0 in a major one. New fields and metrics are minor, fixes
are patches.

A deployment pins a tag: the dbt package from the git tag with its
subdirectory (`sources/ga4`, `sources/shopify`, `sources/woocommerce`,
`sources/sensor_community`),
the Ossie model from the same tag. Upgrading is changing the tag and
running `dbt build --full-refresh`: a package never writes its input
tables, so every canonical table rebuilds from them. The changelog marks
releases that need the rebuild.

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
