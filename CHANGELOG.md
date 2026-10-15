# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/) as the README's
[Versioning](README.md#versioning) section applies them. Every release
names the Ossie schema version its models carry.

## [Unreleased]

### Fixed

- `dbt source freshness` works on dbt v2: each package carries
  ClickHouse versions of dbt's freshness macros
  (`macros/freshness.sql`), since dbt v2's own fail for every source
  ([dbt-labs/dbt#16714](https://github.com/dbt-labs/dbt/issues/16714)).
  A project that installs the packages turns them on with a `dispatch`
  setting (README). Ages match dbt v1's. CI runs freshness on both
  versions, on a ClickHouse server outside UTC, and checks each age
  against ClickHouse's own.
- The README's `packages.yml` example installed all three packages, and
  dbt stops on it: Shopify and WooCommerce write the same tables. It now
  installs GA4 and one store's package, and says that stores on both
  platforms build into separate target databases.
- WooCommerce's `refunds` started each incremental run's window at the
  store's latest refund: a store whose last refund was a month old
  reread a month of changes on every run, and a store without refunds
  reread every order
  ([#18](https://github.com/Dactopus/dactopus-data-models/issues/18)).
  It now keeps the latest sync it has read in its table's comment
  (`read through <time> UTC`) and starts the next window there. On
  320,000 synthetic orders whose only refunds were two years old, the
  `refunds` model's read in one run fell from 80 million rows (2.1 s)
  to 4.8 million (0.3 s).
  The rows are the same. The first run after the upgrade starts from the
  latest refund, as before, and writes the comment; no rebuild is
  needed. Each run rewrites the comment, so a comment set on that table
  is lost, and the dbt user needs `ALTER MODIFY COMMENT` on it (part of
  `ALTER TABLE`, separate from `ALTER DELETE`).

## [0.3.0] - 2026-10-14

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.7.0,
dbt v2 (`dbt-oss` 2.0.5) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. A Shopify deployment needs one
`dbt build --full-refresh` after the upgrade: its `orders` has new
columns, and an incremental run now stops on them with an error instead
of leaving the old table. Shopify's numbers are unchanged. The GA4
package and its model are unchanged.

### Added

- WooCommerce package `sources/woocommerce`: a dbt project that builds
  `orders`, `order_lines`, `refunds` and `sales_events` from seven of the
  store's order tables (HPOS, WooCommerce 8.2 and later), copied from
  MySQL into ClickHouse by change data capture as PeerDB writes them
  (`sources/woocommerce/input.sql`). The package takes the latest version
  of each row and drops deleted ones, and reads empty values in either
  form PeerDB writes them. Incremental by sync time, with a re-read
  window (`woocommerce_lookback_days`, default 3); an incremental run
  also removes orders deleted or moved to the trash, and lines removed
  from an order. The numbers
  follow WooCommerce Analytics under the settings the package's variables
  repeat: the date type (`woocommerce_date_type`, default `date_paid`)
  and the excluded statuses (`woocommerce_excluded_statuses`, default
  pending, cancelled and failed). Other variables name the store's
  currency (required), time zone, price decimals and table prefix,
  plugins' statuses and a sequential order number plugin's meta key.
  Orders WooPayments or FOX placed in another currency are converted to
  the store's as the plugin converts them for Analytics. A cancelled
  order has a `net_total` of 0 unless the store's reports count cancelled
  orders, in which case it is a sale like any other. Structural checks as
  dbt tests, three singular tests (amounts add up; lines make the
  subtotal, a warning outside CI; an order's sales events make its
  `net_total`) and a unit test of the conversion.
  Checked against Analytics on a local test store.
- Hand-written WooCommerce rows in CDC form and the numbers the model must
  answer over them (`tests/woocommerce`, 18 questions), checked in CI on
  both dbt versions, with databases and a table prefix other than the
  defaults. CI syncs part of the rows late, step by step, and checks that
  the incremental build matches a full refresh after each, that the input
  with Nullable columns builds the same tables, and that a store whose
  reports count cancelled orders gets them as sales.
- Dataset `sales_events` in `entities/commerce.yaml`, built by both order
  packages: one row for each order on `order_date`, each refund on the
  day it was made and, at Shopify, each cancellation on the day of the
  cancel for what the refunds did not take back
  ([#14](https://github.com/Dactopus/dactopus-data-models/issues/14)).
- Field `orders.in_sales_reports`: whether the store's own sales reports
  count the order. Always true at Shopify; at WooCommerce, the order's
  status is not excluded and it has the date the reports go by.
- Metrics `all_orders` and `all_orders_total`, over every order, the ones
  the reports leave out included, such as orders awaiting payment.
- Shopify `orders` gets the columns `in_sales_reports` and
  `cancelled_time`, and a singular test that an order's sales events make
  its `net_total` (a warning outside CI).
- README: a WooCommerce quick start on those rows, a recipe for a store
  through PeerDB, the known differences from WooCommerce Analytics and
  the package's known limits.

### Changed

- `net_revenue` reads `sales_events` (`SUM(sales_events.amount)`). By
  `sales_events.event_date`, `event_week` or `event_month` it gives the
  sales of a period as the store's reports do, a refund or a cancellation
  in the period it was made. By `orders.order_month` it gives the same
  numbers as before: what each month's orders earned, later refunds
  included
  ([#14](https://github.com/Dactopus/dactopus-data-models/issues/14)).
- Every metric but `all_orders` and `all_orders_total` counts only orders
  with `in_sales_reports`. At Shopify every order has it, so the numbers
  do not change.
- `order_date` and `order_time` are the date and time the store's reports
  date the order by: unchanged at Shopify (placed), the date of payment
  by default at WooCommerce.
- The commerce model's instructions and descriptions name both sources
  where they differ. The order entities are no longer provisional.
- Both order packages set `on_schema_change: fail`, so a release that
  changes a model's columns stops an incremental run with dbt's error
  instead of leaving the old table.
- Shopify fixture: order 1010 is cancelled on October 2, a week after it
  was placed, with a refund of no money, as Shopify records the cancel of
  an unpaid order. The Shopify checks ask 18 questions.
- `ROADMAP.md`: WooCommerce is done; nothing is next yet.

### Fixed

- The description of `average_order_value` said WooCommerce Analytics
  subtracts refunds before dividing; it does not (checked on a test store
  and in its code), and both platforms define it alike.

## [0.2.1] - 2026-10-13

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.7.0,
dbt v2 (`dbt-oss` 2.0.5) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The packages and the models
answer the same numbers as in 0.2.0: no rebuild is needed.

### Changed

- The README, CONTRIBUTING.md and CI install ossie-clickhouse 0.3.1
  instead of 0.2.2, which could regroup the operators of a compound
  expression under another operator, such as a metric in a filter
  (`1000 / metric > 1`), and return wrong values without an error. The
  models are unchanged and answer the same numbers on 0.2.2 and 0.3.1.
- ossie-clickhouse is now dactopus-ossie-clickhouse: the README,
  CONTRIBUTING.md, CI and `tests/ask_model.py` install and run it under
  that name, at 0.4.0. Its old command still works in 0.4.x; the models
  are unchanged.
- The README, CONTRIBUTING.md and CI install dactopus-ossie-clickhouse
  0.7.0. Since 0.5.0 it answers metrics of two fact tables in one
  question, such as net revenue and refunds by shipping country, merged
  on the dimensions; the README and AGENTS.md list its limits as they
  are now. The models are unchanged and pass the same checks on 0.7.0.
- The README and the description of `refunded_amount` name the report
  metric they compare with as "sales reversals (formerly returns)":
  Shopify renamed it in March 2026, with the same definition
  ([#9](https://github.com/Dactopus/dactopus-data-models/issues/9)).

## [0.2.0] - 2026-10-06

Ossie schema `0.2.0.dev0`. Requires ossie-clickhouse 0.2.2 or later.
Tested with dbt v2 (`dbt-oss` 2.0.5) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The GA4 package and its model
are unchanged: a GA4 deployment needs no rebuild.

### Added

- Shopify package `sources/shopify`: a dbt project that builds `orders`,
  `order_lines` and `refunds` from four input tables filled from the
  GraphQL Admin API (`sources/shopify/input.sql`). The input is a log of
  versions: a loader appends the orders that changed, whole, and the
  package reads the latest version of each order and refund, so
  delivering a version twice is harmless. Incremental by load time, with
  a re-read window (`shopify_lookback_days`, default 3). Order and refund
  dates are in the shop's time zone (`shopify_timezone`, default UTC).
  Databases come from the deployment: the dbt target and the variable
  `shopify_input_database` (default `shopify_raw`). Test orders, tips and
  gift cards sold are left out and refunds count as Shopify's sales
  reports count returns; statuses map to canonical values. Structural
  checks as dbt tests, a singular test that amounts add up, and unit
  tests. The test-order filter, statuses and customer order sequence are
  adapted from Fivetran's
  [dbt_shopify](https://github.com/fivetran/dbt_shopify) (Apache 2.0).
- Ossie model `entities/commerce.yaml` over those tables: 3 datasets,
  2 relationships, 42 fields, 17 metrics (orders, revenue, net revenue,
  refunds, refund rate, average order value, items, discounts, shipping,
  tax, customers, repeat orders). Its fields are those WooCommerce
  provides too; it is provisional until a second orders package maps
  onto it.
- Hand-written Shopify rows and the numbers the model must answer over
  them (`tests/shopify`), checked in CI on both dbt versions. CI also
  loads part of the rows late and checks that the incremental build
  matches a full refresh row for row.
- README: a Shopify quick start on those rows, a recipe for loading a
  store through the GraphQL Admin API, what the commerce model answers,
  the known differences from Shopify's reports and the package's known
  limits, among them the memory a first build needs on a large shop.
- A diagram of how the packages work with their sources, ClickHouse, BI
  tools and AI agents: an image in the README and an interactive page on
  GitHub Pages (`docs/`).
- README: the metrics the GA4 model answers, and the known differences
  from the GA4 interface.
- `ROADMAP.md`: what comes next, without dates. The README links to it
  instead of listing planned sources as if they existed. WooCommerce is
  next.

### Fixed

- README: the opening of 0.1.0 listed orders, line items and customers
  as available before any of them were; the Quick start names
  ossie-clickhouse with its MCP server among the requirements. Its example of how sources differ no longer
  states an unchecked claim about Shopify and WooCommerce refunds.

## [0.1.0] - 2026-10-05

Ossie schema `0.2.0.dev0`. Requires ossie-clickhouse 0.2.2 or later: the
model names its tables without a database. Tested with dbt v2 (`dbt-oss`
2.0.5) and dbt v1 (`dbt-core` 1.11 with `dbt-clickhouse` 1.10) on
ClickHouse 26.9.

### Added

- GA4 package `sources/ga4`: a dbt project that builds `events`,
  `sessions` and `purchases` from the BigQuery export, loaded into the
  input table `sources/ga4/input.sql`. Incremental with a three-day
  re-read window; structural checks as dbt tests. Installs from a git tag
  with `subdirectory: sources/ga4`. Databases come from the deployment:
  the dbt target (`CLICKHOUSE_DATABASE` in the package's own profile,
  default `dactopus`) and the variable `ga4_input_database` (default
  `ga4_raw`).
- Ossie model `entities/web_analytics.yaml` over those tables: 3 datasets,
  2 relationships, 12 metrics (sessions, engagement, users, conversion,
  purchases, revenue, average order value, events, page views). Revenue
  is in each purchase's own currency (`purchases.currency`); the model
  tells agents to break it down by currency and never to add amounts in
  different currencies.
- Hand-written GA4 rows and the numbers the model must answer over them
  (`tests/ga4`), checked in CI on both dbt versions.

[Unreleased]: https://github.com/Dactopus/dactopus-data-models/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.1.0
