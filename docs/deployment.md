# Deployment

How the packages and the Ossie models go into a dbt project and are
served to agents: the input databases, the label of each store, property
or network, the time zones, and the unions that add up several of them.
Each package's own settings and loading recipe are in its README
([GA4](../sources/ga4/README.md), [Shopify](../sources/shopify/README.md),
[WooCommerce](../sources/woocommerce/README.md),
[Sensor.Community](../sources/sensor_community/README.md)).

## Use in your dbt project

Add the packages you need to your project's `packages.yml`, pinned to a
release tag: GA4 and your store's package, here Shopify (for
WooCommerce, `subdirectory: sources/woocommerce`; for Sensor.Community,
`sources/sensor_community`):

```yaml
packages:
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.9.0
    subdirectory: sources/ga4
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.9.0
    subdirectory: sources/shopify
```

The Shopify and WooCommerce packages write the same tables, so a project
installs one of them: with both, dbt stops before building anything. A
business with a store on each builds them into separate target
databases, as for [several stores](#several-stores-properties-or-networks).

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
differ from WooCommerce's (the WooCommerce package's [Your store](../sources/woocommerce/README.md#your-store), step 4). The WooCommerce package
needs ClickHouse 26.7 or later, and its dbt user needs
`ALTER MODIFY COMMENT` on `refunds` (the WooCommerce package's [Your store](../sources/woocommerce/README.md#your-store), step 5).

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
commit late. `ga4_lookback_days` (default 3) is how many days before the
latest day it has built an incremental run rereads: Google updates a
day's export table for up to 72 hours after its date
([export schedule](https://support.google.com/analytics/answer/9358801)).

Every row of every table carries the label of its property, store or
network in `source_id`, from `ga4_source_id`, `shopify_source_id`,
`woocommerce_source_id` or `sensor_community_source_id`, whose default
is the package's name (`shopify`). A label is 1 to 64 of `a-z`, `0-9`
and `_`; the build stops on any other. The Ossie models put `source_id`
first in the key of every dataset that has one and join on it, so the
tables of two stores, each built with its own label, keep their orders
and customers apart. A new label needs `dbt build --full-refresh`: an
incremental run labels only the rows it rebuilds, and the package's
tests then fail with a message that says so.

Each package's `deployment.yml` lists what a deployment sets and reads:
the Ossie model its tables serve, the variables above by their role
(input database, label, time zone) and the tables a deployment counts rows per
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
the profile of [Quick start](../README.md#quick-start) does: the v2
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

## Several stores, properties or networks

Build each store, GA4 property or Sensor.Community network with its
package into a target database of its own, under a label of its own
(`shopify_source_id` and the like, [Use in your dbt
project](#use-in-your-dbt-project)). Each GA4 property exports to its own
BigQuery dataset, and each site of a WordPress multisite is a store with
its own table prefix. A union then adds up their tables for one domain:
`unions/commerce`, `unions/web_analytics` and `unions/iot` are dbt
projects that write, to a database of their own, a view of each table
the domain's Ossie model reads, `UNION ALL` over the databases a
variable lists. A commerce union takes Shopify and WooCommerce stores
alike.

```bash
dbt build --project-dir unions/commerce --vars '{commerce_union_databases: [main_store, outlet_store, wholesale_store]}'
```

The union is a dbt project of its own, with its database as the target:
built from a checkout of the release tag, or installed as the only
package of a project (`subdirectory: unions/commerce`, its variable
under `dactopus_commerce_union`). Its views have the packages' table
names, so dbt stops a project that installs a package beside it.

- **Columns.** A view has the columns the Ossie model reads and no
  others; a package's own columns (`tip_total`, `fee_total`) stay in the
  store's database. Each column has the type every package gives it, and
  the build stops on a database whose table gives another, as one built
  by an earlier release would, and names the column.
- **Tests.** `dbt build` fails when a label is in two of the databases,
  as for two stores built under the package's default. Each package
  tests its keys when it builds, so with a label of its own in each
  database, every key is unique in the union. The union's own database is
  not one of those it adds up: its views would replace the tables they
  read, and the build stops before.
- **Views.** The union holds no rows of its own and sees a store's
  tables as soon as its build finishes. Build it again after adding a
  database and after a release changes the packages' columns.
- **Answers.** Serve the domain's Ossie model over the union's database.
  Each store's numbers are the ones it gives alone, `orders.source_id`
  splits them, and a total adds them up. Customers and products belong
  to their store: a customer of two stores counts twice. Amounts are in
  each store's currency, and the model converts none: its instructions
  have an agent ask every amount by `orders.currency` and never add up
  two currencies, while a query of your own that leaves the currency
  out adds them up as they are. Each store's dates are in its own time
  zone, and `--time-zone` sets one "today" for all of them. A GA4 user
  belongs to a property, as a customer to a store: a browser that
  visited two sites counts in each. A sensor network's silent devices
  count from that network's own latest contact.
- **Labels.** Agents know a store, property or network by its label,
  and a store also by its currency and its platform (`orders.platform`);
  the model has no country or market. Give labels that name what people
  call them (`usa_store`, `wholesale_store`); an agent asked about "the US
  store" picks the label that names it, and asks when none does. An
  order, customer, product or device id is unique within its label only.
- **`deployment.yml`.** A union's file names its Ossie model and the variable
  that lists the databases (role `input_databases`). Rows per day are
  counted in the stores' databases, by their packages' files.

`uv run tests/check_union.py entities/commerce.yaml <union url> <store
url>...` asks the model over the union and over each store's database
and compares: each label's answers must be its store's own.
