# WooCommerce package

Maps a WooCommerce store's order tables, copied into ClickHouse by
change data capture (CDC), onto the `commerce` entities: `orders`,
`order_lines`, `refunds`, `sales_events`, `customers`, `products`,
`line_categories`, `line_brands`, `order_discount_codes`,
`product_categories` and `product_brands`. What the model answers and
how it defines sales, categories and customers: [docs/commerce.md](../../docs/commerce.md).
Installing the package in a dbt project, time zones and several stores:
[docs/deployment.md](../../docs/deployment.md).

## Quick start

Try the package on the rows the repository tests it with,
[`tests/woocommerce/fixture.sql`](../../tests/woocommerce/fixture.sql): sixteen
orders and four refunds of a store in New York, as change data capture
(CDC) writes them, each a case the package must get right (refunds with
and without lines, a cancelled order, cash on delivery, fees, tax included
in prices, rows updated and then deleted, a deleted product, an order in
the trash, an order paid in EUR), with a catalog of seven products in
nested categories and with brands (a product in two categories, a
category moved under another, two categories of one name, a product in
the trash). You need ClickHouse, dbt and
dactopus-ossie-clickhouse, as in the README's [Quick start](../../README.md#quick-start). The package needs ClickHouse 26.7
or later: its models compute each shared subquery once
(`WITH ... AS MATERIALIZED`), which fails on earlier versions. CI runs it
on 26.7 and 26.9.

1. **Load** the package's input tables
   [`sources/woocommerce/input.sql`](input.sql) and the
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
   asks 45 questions, in the zone of step 2, and compares the answers
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

## Your store

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
   [`input.sql`](input.sql) lists those the package
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
   | `woocommerce_source_id` | `woocommerce` | the store's label in every row (`source_id`, [docs/deployment.md](../../docs/deployment.md)) |

   An order in a status that is neither core nor mapped fails the build,
   and so does an order in another currency without a rate the package
   knows (Known limits below).

5. **Next runs.** CDC keeps the input current; run `dbt build` again,
   and it is incremental. It rereads the orders with a row synced in the
   `woocommerce_lookback_days` (default 3) before the latest sync it has
   seen. `refunds` has no row for an order without refunds, so it keeps
   that sync in its table's comment, rewritten on each run; the dbt user
   needs `ALTER MODIFY COMMENT` on it and on `orders` and `order_lines`,
   which keep the settings they were built with in theirs (Changing a
   setting, below; the privilege is part of `ALTER TABLE`). `orders`
   keeps the orders a run rereads in `orders__changed` and drops it at
   the end; a run that fails leaves it, and the next run rereads its
   orders too.
   `dbt source freshness` warns when CDC has not synced
   an order for a day; a store without an order in a day warns too.


## Changing a setting

`orders`, `order_lines` and `refunds` are incremental: a run rebuilds
only the orders the input changed and keeps the other rows as they were
built. Eight variables decide the values of the rows already built, so a
change of any of them needs `dbt build --full-refresh` once:

- `woocommerce_timezone`: the day of every order and refund.
- `woocommerce_date_type` and `woocommerce_excluded_statuses`: which
  orders the reports count, and the date they count them on.
- `woocommerce_order_statuses`: the core status of an order in a plugin's
  status.
- `woocommerce_currency` and `woocommerce_price_decimals`: the amounts
  converted from another currency.
- `woocommerce_order_number_meta_key`: the number an order shows.
- `woocommerce_source_id`: the `source_id` of every row.

The three tables record the values they were built with in their
comments (`built with {...}`, after the sync position of `refunds`), and
an incremental run that finds other values stops before it reads or
deletes a row of them, naming each variable with its old and new value.
The tables a run builds whole before it reaches them,
`product_categories_all` and `product_brands_all`, may already carry the
new label when it stops; the full refresh brings all of them in line and
records the new values. A table built by release 0.11.2 or earlier
records none, so its first run stops the same way; the full refresh the
next release needs for its new column covers it. `woocommerce_input_database`,
`woocommerce_table_prefix` and `woocommerce_lookback_days` can change in
any run.


## Known differences from WooCommerce Analytics

The package is checked against WooCommerce Analytics (11.2) under each
of its three date types, other settings as WooCommerce ships them.
Every order's total, subtotal, tax, shipping, items, refunds, report
date and whether the reports count it match.
`sales_events.net_revenue` by `sales_events.event_month` equals the
reports' total sales for every month, and `orders.order_count`,
`orders.average_order_value`, `orders.items_per_order`,
`orders.discount_amount`, `order_lines.items_net`, refunds by month, each
order's new or returning and the customers' total spend equal the
reports' numbers.
`orders.average_order_value` filtered by a category equals the Orders
report filtered by it, subcategories included. After a refund, a deleted
order and a new one, an incremental run matches a full rebuild and the
reports. Other numbers differ by definition, and the model's
descriptions say how:

- **Net sales** in the reports are goods after refunds, without shipping
  and tax. `sales_events.net_revenue` is the reports' total sales;
  `order_lines.line_revenue` is goods after discounts, before refunds.
- **Shipping and tax** in the reports are net of what was refunded, in
  the month of the refund; `orders.shipping_amount` and
  `orders.tax_amount` are as on the order.
- **Customers**: the reports count a guest as a customer by email, and
  so does the model. Analytics keeps its own table of customers, where an
  account has the account's own email; the model reads only the orders
  and joins a guest's orders to an account that has an order billed to
  the same email, whichever of the two ordered first. The two differ in
  rare cases. An account's order billed to another email: the model
  joins that email's guest orders to the account, Analytics keeps the
  guest a customer of their own. A guest who orders with an
  account's own email, which none of the account's orders carries: the
  model keeps the guest a customer of their own, Analytics joins them to
  the account when it registered first.
- **Buyers in a month**: `total_customers` in the Revenue and Orders
  reports also counts a customer whose only row in the month is a refund
  of an earlier month's order; `orders.buyer_count` counts customers with
  an order dated in the month.
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
