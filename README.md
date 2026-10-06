# dactopus-data-models

[![CI](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Dactopus/dactopus-data-models)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Dactopus/dactopus-data-models)](https://github.com/Dactopus/dactopus-data-models/releases)

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format. Two kinds of content:

- **Canonical entities**: sessions, events and purchases from web
  analytics; orders, their lines and refunds from the store. They have
  the same shape whatever the data came from.
- **Source packages**: each maps one source onto those entities. GA4 and
  Shopify are available.

What comes next is in [ROADMAP.md](ROADMAP.md).

The aim: a store on Shopify and a store on its own Postgres look the same
once both are mapped, and one query works on both. The same model serves
BI tools through ClickHouse tables and AI agents through
[ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse).

<a href="https://dactopus.github.io/dactopus-data-models/"><img src="docs/architecture.svg" width="680" alt="How the packages work: the GA4 export and Shopify's orders are loaded into input tables in your ClickHouse; the dbt packages build the canonical tables; BI tools read them directly and AI agents through ossie-clickhouse and the Ossie models."></a>

Click the diagram for the [interactive version](https://dactopus.github.io/dactopus-data-models/):
what each part does and where it takes its settings from, and one
purchase followed from GA4 to an AI agent's answer.

## Sources

| Source | Entities | Status |
| --- | --- | --- |
| GA4 (BigQuery export) | `events`, `sessions`, `purchases` | available |
| Shopify (GraphQL Admin API) | `orders`, `order_lines`, `refunds` | available |
| WooCommerce | `orders`, `order_lines`, `refunds` | [next](ROADMAP.md#next) |

The order entities are provisional until a second orders source maps onto
them. One source alone cannot show which fields are canonical: until
then, a field goes into them only when WooCommerce provides it too,
checked against its documentation.

## Quick start

### GA4

Try the GA4 package on Google's public sample
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset):
4.3 million events from November 2020 to January 2021. You need
[ClickHouse](https://clickhouse.com/docs/install), the
[gcloud CLI](https://cloud.google.com/sdk/docs/install),
[uv](https://docs.astral.sh/uv/), dbt v2 (`pip install dbt-oss`) and
[ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse) 0.2.2 or
later with its MCP server
(`pip install "ossie-clickhouse[mcp] @ git+https://github.com/Dactopus/ossie-clickhouse@v0.2.2"`).
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

3. **Build** the canonical tables. Connection settings come from
   `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP, default 8123),
   `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`; the database the tables go
   to from `CLICKHOUSE_DATABASE` (default `dactopus`).

   ```bash
   dbt build --project-dir sources/ga4 --profiles-dir sources/ga4
   ```

4. **Validate** the model against the built tables. The model names its
   tables without a database: ossie-clickhouse reads them in the database
   of its URL.

   ```bash
   ossie-clickhouse validate entities/web_analytics.yaml --url http://user:password@host:8123/dactopus
   ```

5. **Ask.** Serve the model to an AI agent over MCP with
   `ossie-clickhouse serve entities/web_analytics.yaml --url ...`, the
   same URL; its [README](https://github.com/Dactopus/ossie-clickhouse#readme)
   shows how to connect an agent. Try sessions, conversion rate and
   revenue, by traffic source, device, country and date.

### Shopify

There is no public Shopify export, so try the package on the rows the
repository tests it with,
[`tests/shopify/fixture.sql`](tests/shopify/fixture.sql): twelve orders
of a shop in New York, each a case the package must get right (refunds,
cancellations, discounts, tax included in prices, a gift card, a tip,
import duties, repeated deliveries). You need ClickHouse, dbt and
ossie-clickhouse, as for GA4.

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
   CLICKHOUSE_DATABASE=shopify_sample dbt build --project-dir sources/shopify --profiles-dir sources/shopify \
       --vars '{shopify_input_database: shopify_sample_raw, shopify_timezone: America/New_York}'
   ```

3. **Validate** the model and **check** its answers: `check_numbers.py`
   asks 16 questions through ossie-clickhouse and compares the answers
   with numbers worked out by hand from the rows.

   ```bash
   ossie-clickhouse validate entities/commerce.yaml --url http://user:password@host:8123/shopify_sample
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/shopify_sample python3 tests/shopify/check_numbers.py
   ```

4. **Ask.** Serve `entities/commerce.yaml` with `ossie-clickhouse serve`.
   Try net revenue, refunds by month, average order value and repeat
   orders, by shipping country and new or returning customer.

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

2. **Export** the orders updated since a time. Save the script below as
   `export_shopify.py` and run it with the store's subdomain and the
   token; the first time, from a date before the store's first order:

   ```bash
   SHOPIFY_SHOP=<store> SHOPIFY_TOKEN=<token> python3 export_shopify.py 2000-01-01T00:00:00Z data/shopify
   ```

   It reads the GraphQL Admin API (version 2026-10) 25 orders at a
   time, each with its lines and refunds, and writes one JSON file per
   input table, with only the columns `input.sql` declares. It needs only
   Python. A Shopify bulk operation would be faster on a large store, but
   it cannot read refund lines, which sit inside the list of an order's
   refunds.

   <details><summary>export_shopify.py</summary>

   ```python
   import json, os, pathlib, sys, time, urllib.request
   from decimal import Decimal

   shop, token = os.environ["SHOPIFY_SHOP"], os.environ["SHOPIFY_TOKEN"]
   since, out = sys.argv[1], pathlib.Path(sys.argv[2])
   API = f"https://{shop}.myshopify.com/admin/api/2026-10/graphql.json"
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


   def fetch(variables):
       while True:
           req = urllib.request.Request(API, json.dumps({"query": QUERY, "variables": variables}).encode(),
                                        {"X-Shopify-Access-Token": token, "Content-Type": "application/json"})
           body = json.load(urllib.request.urlopen(req))
           if any(e.get("extensions", {}).get("code") == "THROTTLED" for e in body.get("errors", [])):
               time.sleep(2)
               continue
           if "errors" in body:
               sys.exit(body["errors"])
           return body["data"]["orders"]


   def money(v): return str(Decimal(v["shopMoney"]["amount"])) if v else "0"
   def total(items, key): return str(sum((Decimal(i[key]["shopMoney"]["amount"]) for i in items), Decimal(0)))
   def legacy(gid): return int(gid.rsplit("/", 1)[1])
   def ts(v): return v and v.replace("T", " ").rstrip("Z")
   def nodes(conn, what):
       if conn["pageInfo"]["hasNextPage"]:
           sys.exit(f"more than 50 {what} in one order or refund: raise first: in the query")
       return conn["nodes"]


   tables = {t: [] for t in ("orders", "order_lines", "refunds", "refund_lines")}
   page = {"pageInfo": {"hasNextPage": True, "endCursor": None}}
   while page["pageInfo"]["hasNextPage"]:
       page = fetch({"cursor": page["pageInfo"]["endCursor"], "filter": f"updated_at:>='{since}'"})
       for o in page["nodes"]:
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
   for t in orders order_lines refunds refund_lines; do
       if [ -s data/shopify/$t.jsonl ]; then
           clickhouse client --query "INSERT INTO shopify_raw.$t FORMAT JSONEachRow" < data/shopify/$t.jsonl
       fi
   done
   ```

4. **Build** with the shop's time zone (Settings > General in the admin)
   as `shopify_timezone`, then validate and ask as above, at the
   database the tables went to (`CLICKHOUSE_DATABASE`, default
   `dactopus`).

5. **Next loads.** Export from an hour before the latest change already
   loaded, load, and build again: the build is incremental. A refund or a
   cancellation changes an order's `updated_at`, so the export delivers
   the order again, whole; delivering the same version twice is harmless.

   ```bash
   since=$(clickhouse client --query "SELECT formatDateTime(max(updated_at) - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%SZ') FROM shopify_raw.orders")
   SHOPIFY_SHOP=<store> SHOPIFY_TOKEN=<token> python3 export_shopify.py "$since" data/shopify
   ```

   Orders deleted in Shopify are not exported again, so they stay in the
   input tables.

## What the GA4 model answers

[`entities/web_analytics.yaml`](entities/web_analytics.yaml) has 12
metrics:

- sessions: `sessions`, `engaged_sessions`, `engagement_rate`, `users`,
  `session_conversion_rate`, `user_conversion_rate`, `page_views`. They
  break down by the session's date, week and month; traffic source,
  medium and campaign; landing page, device and country.
- purchases: `purchases`, `revenue`, `revenue_usd`, `average_order_value`.
  They break down by the session fields above, and by the purchase's own
  date, week, month and currency.
- events: `events`. It breaks down by the session fields above, and by
  the event's own date, name, page, device and country.

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
  `revenue_usd` is converted by Google at a rate it does not document.
- **Dates** are in the GA4 property's time zone; a session that crosses
  midnight counts once, on the day it started. Properties outside UTC
  are not tested yet ([#1](https://github.com/Dactopus/dactopus-data-models/issues/1)).

## What the commerce model answers

[`entities/commerce.yaml`](entities/commerce.yaml) has 17 metrics:

- orders: `orders`, `revenue`, `net_revenue`, `refunded_amount`,
  `refund_rate`, `average_order_value`, `items_per_order`,
  `discount_total`, `shipping_total`, `tax_total`, `customers`,
  `repeat_order_share`. They break down by the order's date, week and
  month; payment and fulfillment status, cancelled or not, channel and
  currency; shipping country, region and city; new or repeat customer.
- order lines: `items_sold`, `items_net`, `line_revenue`. They break down
  by product, variant, SKU and title, and by the order fields above.
- refunds: `refunds`, `refunds_total`. They break down by the refund's
  own date, week and month, and by the order fields above.

"Sales" or "revenue" without a qualifier is `net_revenue`: orders less
cancelled ones and less refunds, with shipping and tax. `revenue` is
orders as placed. Amounts are in the store's currency.

## Known differences from Shopify's reports

On the development store the package was checked against, `net_revenue`
equals Shopify's total sales, overall, by month, by shipping country, by
new or returning customer and for each order, and `average_order_value`
equals the store's. Test orders are left out, as in the reports. Other
numbers differ by definition, and the model's descriptions say how:

- **Gross and net sales** in Shopify's reports are goods only.
  `revenue` and `net_revenue` add shipping, tax and import duties;
  `line_revenue` is goods after discounts.
- **Returns** in the reports are without tax and count a cancelled unpaid
  order as returned. `refunded_amount` is the money paid back, with its
  tax; a cancelled unpaid order has nothing refunded, and `net_revenue`
  leaves it out.
- **Taxes** in the reports are net of refunded tax; `tax_total` is the
  tax on the order as placed.
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

Known limits of the package: a custom item with no product, no tax and
nothing to ship that costs exactly the order's tip is taken for the tip;
a line's tax rates are added up, so compound taxes are not exact; orders
deleted in Shopify stay; amounts are in the shop's currency, not the
currency the customer paid in.

## Use in your dbt project

Add the packages you need to your project's `packages.yml`, pinned to a
release tag:

```yaml
packages:
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.2.0
    subdirectory: sources/ga4
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.2.0
    subdirectory: sources/shopify
```

The GA4 package writes `events`, `sessions` and `purchases` to your
target's database and reads its input from `ga4_raw.events`. The Shopify
package writes `orders`, `order_lines` and `refunds` and reads its input
from the four tables in `shopify_raw`. Name other databases, and set the
shop's time zone: without it, every Shopify date is in UTC and orders
near midnight fall on the wrong day.

```yaml
vars:
  dactopus_ga4:
    ga4_input_database: my_ga4_export
  dactopus_shopify:
    shopify_input_database: my_shopify_export
    shopify_timezone: Europe/Berlin
```

`shopify_lookback_days` (default 3) is how far before its last load an
incremental run rereads the input, for inserts that commit late.

Point ossie-clickhouse at your target's database
(`--url http://host:8123/<database>`) and take the Ossie models from the
same tag. On dbt v2 with ClickHouse 26.x, set
`custom_settings: {network_compression_method: LZ4}` in your profile, as
[`sources/ga4/profiles.yml`](sources/ga4/profiles.yml) does: the v2
ClickHouse adapter (beta) cannot read ClickHouse's default ZSTD
responses.

Several GA4 properties: each exports to its own BigQuery dataset. Build
the package once per property, each with its own input and target
database, and serve the model once per target. A total across properties
is not modelled. The same holds for several Shopify stores.

## Layout

    entities/<domain>.yaml    one Ossie model per domain (web_analytics, commerce)
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      models/                 one model per entity, named after it
      models/schema.yml       structural checks (dbt tests)
      tests/                  checks that need their own SQL
    tests/<source>/           hand-written input rows and the numbers the
                              model must answer over them
    docs/                     the diagram above and its interactive page

A package's model writes the entity's table, named after it, in the
database the deployment chooses. The entity's dataset in the domain's
Ossie model names that table without a database (an Ossie model is one
file, since relationships and metrics span entities), so one model serves
any database ossie-clickhouse connects to, and
`ossie-clickhouse validate --url` checks that the package delivers every
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
- Running queries. That is ossie-clickhouse.
- Reconciling with the source's own reports through its API.
- Anything that needs two sources at once: attributing sessions to
  orders, matching customers across systems, cross-source marts.
- API connectors (for example to the GA4 API) and Universal Analytics.

Everything here is Apache 2.0. If a file cannot be released under it, it
does not belong here.

## Authoring rules

**Format.** Ossie schema `0.2.0.dev0`, the only version the upstream
schema accepts today. Write expressions in `ANSI_SQL`; ossie-clickhouse
also accepts `OSSIE_SQL_2026`. Mapping, refresh and checks live in the
package's dbt project, not in the Ossie files, so entities stay plain Ossie
that any Ossie tool reads. The only extension used is ossie-clickhouse's
`CLICKHOUSE` namespace and its `dedup` key.

**The canon is selected, not designed.** A field that at least two sources
provide goes into the canonical entity. While a domain has a single source
(GA4 for events), a field qualifies when its meaning does not depend on
that source. Where the second source is known but not yet packaged
(WooCommerce for orders), the field must exist there too, checked against
its documentation. A field only one source has is not modelled until a
second source needs it.

**Descriptions are part of the model.** Agents answer from descriptions,
synonyms and `ai_context`. Without them even strong models guess. A dbt
`.yml` description is the minimum, not the target.

**Name the "obvious" choices.** Models break on what looks obvious:
- Order date: placed, paid or shipped? Store time zone or UTC?
- Customer: account, email or card?

A package states which one it uses and why.

**ossie-clickhouse limits are rules here.**
- One root dataset per question.
- Joins are many-to-one only, on a declared primary or unique key, so a
  mart that combines facts is materialized as one fact table.
- A metric cannot reference another metric by name; repeat the
  expression.
- No time grain or derived dimensions: declare one field per grain.
- `source` is a table name without a database, not a query: the
  deployment picks the database.

See its [model authoring guide](https://github.com/Dactopus/ossie-clickhouse/blob/main/docs/model-authoring.md).

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
subdirectory (`sources/ga4`, `sources/shopify`), the Ossie model from the
same tag. Upgrading is changing the tag and running
`dbt build --full-refresh`: a package never writes its input tables, so
every canonical table rebuilds from them. The changelog marks releases
that need the rebuild.

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
