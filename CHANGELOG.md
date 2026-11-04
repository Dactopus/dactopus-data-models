# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/) as the README's
[Versioning](README.md#versioning) section applies them. Every release
names the Ossie schema version its models carry.

## [Unreleased]

## [0.12.0] - 2026-11-04

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.13.0
(the canon and the blind questions) and 0.12.0 (CI), dbt v2 (`dbt-oss`
2.0.11) and dbt v1 (`dbt-core` 1.11 with `dbt-clickhouse` 1.10) on
ClickHouse 26.9, the WooCommerce package also on 26.7. Needs
`dbt build --full-refresh` once.

`order_lines`, `line_categories`, `line_brands` and `refunds` of both
packages and of the commerce union gain a column: an incremental run
stops on the changed schema, and a deployment runs
`dbt build --full-refresh` once. The same full refresh records the
settings the new check below needs. No input table changes. Metric names
of the commerce model change.

### Changed

- `orders`, `order_lines` and `refunds` of the Shopify and WooCommerce
  packages built by an earlier release record no settings, so their
  first incremental run stops with the message of the check below. The
  full refresh this release needs for the new columns builds them anew
  and records the settings, so one `dbt build --full-refresh` covers
  both.
- The dbt user needs `ALTER MODIFY COMMENT` on `orders`, `order_lines`
  and `refunds` of both packages. The WooCommerce package needed it on
  `refunds` already.
- The 18 commerce metrics that read order lines, their categories and
  brands, or refunds together with `orders.in_sales_reports` are metrics
  of those datasets, as the Ossie spec requires: it rejects an aggregate
  over fields of two datasets, and its relational layer does not expose
  the metrics of the model itself. A question names them
  `dataset.metric`, and result columns are named so too. This breaks
  saved questions, dashboards and agent prompts that ask for the old
  names; the numbers are unchanged:

  | Old | New |
  | --- | --- |
  | `items_sold`, `items_net`, `line_revenue`, `items_returned`, `line_returned_amount`, `line_net_revenue` | the same name on `order_lines`: `order_lines.line_revenue` |
  | `category_items_sold`, `category_revenue`, `category_items_returned`, `category_returned_amount`, `category_net_revenue` | the same name on `line_categories`: `line_categories.category_revenue` |
  | `brand_items_sold`, `brand_revenue`, `brand_items_returned`, `brand_returned_amount`, `brand_net_revenue` | the same name on `line_brands`: `line_brands.brand_revenue` |
  | `refund_count`, `refunds_total` | the same name on `refunds`: `refunds.refunds_total` |

  The model has no metrics of its own any more.
- `order_lines`, `line_categories`, `line_brands` and `refunds` carry
  `in_sales_reports` (`Bool`), the flag of the line's or refund's order
  (`orders.in_sales_reports`), so that the metrics above count the rows
  of one dataset. At Shopify it is true. At WooCommerce the packages
  compute it from the order's status, time placed and payment and
  completion dates, by the formula of `orders` that now sits in the
  macros `woocommerce_report_time` and `woocommerce_in_sales_reports`.
  The commerce union lists the column too.
- `orders.refund_rate`, `orders.average_order_value`,
  `orders.items_per_order` and `orders.repeat_order_share` divide by
  `NULLIF(..., 0)`: a question that matches no counted order gets NULL,
  where it divided by zero.
- `tests/check_contracts.py` fails on a metric that reads fields of more
  than one dataset. `AGENTS.md` and `CONTRIBUTING.md` state the rule,
  and `docs/commerce.md` lists the metrics by dataset.
- The model instructions said every metric but `orders.all_orders` and
  `orders.all_orders_total` counts only the orders the store's sales
  reports count. The metrics of `customers` count the orders the store's
  customers report counts, which at WooCommerce includes an order on hold
  that is not paid yet. The
  instructions and the descriptions of `customers` say so;
  `CONTRIBUTING.md` and `AGENTS.md` state the rule: a dataset built from
  orders says which orders it counts, in the model's terms, and then
  names the store report that counts the same.

### Added

- An incremental run of the Shopify and WooCommerce packages stops, before
  it reads or deletes a row of `orders`, `order_lines` or `refunds`, when
  the variables that decide the values of the rows already built differ
  from the ones the tables were built with.
  Until now a changed variable rebuilt only the orders the run reread and
  left the others as they were, a mixture that no test caught (the
  one-label tests caught a new label, after the run had rewritten rows).
  The message names the table, each differing variable with its old and
  new value, and asks for `dbt build --full-refresh` once. Guarded at
  Shopify: `shopify_timezone`, `shopify_source_id`. At WooCommerce:
  `woocommerce_timezone`, `woocommerce_date_type`,
  `woocommerce_excluded_statuses`, `woocommerce_order_statuses`,
  `woocommerce_currency`, `woocommerce_price_decimals`,
  `woocommerce_order_number_meta_key`, `woocommerce_source_id`. The input
  database, the table prefix and the lookback days are not guarded.
- The values are kept in the comment of `orders`, `order_lines` and
  `refunds`, as `built with {...}` (JSON, keys in alphabetical order),
  written after a first build or a full refresh. At WooCommerce the
  comment of `refunds` also holds its sync position, and each macro
  that writes the comment keeps the segments it does not own
  (`woocommerce_set_comment`). The README of each package has a section,
  Changing a setting.
- Tests `order_lines_in_sales_reports_match_orders` and
  `refunds_in_sales_reports_match_orders` in both packages: no line or
  refund has a flag different from its order's. At WooCommerce they warn
  until `DACTOPUS_STRICT_TESTS=error`, as the package's other tests that
  compare two tables.
- `line_categories.category_tree_items_sold`, `category_tree_revenue`,
  `category_tree_items_returned`, `category_tree_returned_amount` and
  `category_tree_net_revenue`, and
  `product_categories.category_tree_product_count`: the category metrics
  over every row of the line or product, the categories above its own
  included. Filtered by one category (`category_path`), they count the
  category with its subcategories, each line or product once. The
  descriptions advised `order_lines.line_revenue` or
  `products.product_count` filtered by `line_categories.category_path`
  or `product_categories.category_path` for that: a filter on the many
  side of a relationship, which dactopus-ossie-clickhouse answers and
  the Ossie spec's relational and wide-table layers do not express. The
  advice now names the new metrics; `orders.average_order_value`
  filtered by a category keeps the old form, which has no other. The
  tables do not change.

## [0.11.2] - 2026-11-04

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.13.0,
the other versions as in 0.11.0.

### Changed

- The instructions of the three models keep only the rules across their
  datasets and fit in 2,300 characters (`commerce` had 8,367,
  `web_analytics` 3,683, `iot` 2,870). dactopus-ossie-clickhouse puts
  them into its MCP server's instructions, which Claude Code cut at
  4,096 characters: an agent saw a quarter of the `commerce` rules there.
  A rule about one dataset, field or metric moved to its description, and
  one said twice is said once. The tables do not change and no rebuild
  is needed. `tests/check_contracts.py` fails on instructions over 2,300
  characters.

## [0.11.1] - 2026-11-04

Ossie schema `0.2.0.dev0`. Tested with the same versions as 0.11.0.

### Changed

- The descriptions of the three models name the source packages without
  repository paths (`sources/shopify` and the like). The tables do not
  change and no rebuild is needed.
- CI leaves a change of text alone out of the package and union jobs: a
  `dbt_project.yml` whose only changed line is its `version:`, an entity
  whose `description` and `ai_context` alone changed
  (`tests/reach.py`). The validate job still runs on any change to an
  entity. A release's version lines no longer run every package.

## [0.11.0] - 2026-11-04

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.11) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. The models write expressions in the `sql` form, which
dactopus-ossie-clickhouse reads since 0.11.0: an older version, or an
Ossie tool that reads only `dialects`, does not load them. No table
changes and no rebuild is needed.

### Changed

- The models of the three domains write expressions as
  `expression: {sql: ...}` instead of
  `expression: {dialects: [{dialect: ANSI_SQL, ...}]}`, the form of the
  apache/ossie examples and spec since apache/ossie#640. Reading it
  needs dactopus-ossie-clickhouse 0.11.0 or newer. The numbers of the
  models do not change and no rebuild is needed.

## [0.10.0] - 2026-11-03

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. The unions' views read the tables they add up with the rights
of the user who built them, so a user that reads a model needs `SELECT`
on the union's database alone; where row policies on those tables hide
rows from the reader, the numbers through a union change.
`deployment.yml` names the zone of the days of a package that fixes it.
No table changes and no rebuild is needed: a union changes on its next
build.

### Added

- `zone` in `deployment.yml`: the zone of the days of a package that
  fixes it in its model, so a deployment no longer has to be told it.
  The Sensor.Community package declares `zone: UTC`; Shopify and
  WooCommerce take the zone from the variable with the role `time_zone`,
  and GA4's days are in the property's zone; none of the three has the
  key. `zone` and `time_zone` exclude each other, and a union's file has
  no `zone`.
  `tests/check_deployment.py` requires an IANA name and counts in every
  daily table the rows whose date is not the day of their time in
  `zone`, with or without `--time-zone`, and fails on any such row or on
  a `--time-zone` that differs
  ([#60](https://github.com/Dactopus/dactopus-data-models/issues/60)).

- `tests/<source>/canon/` and `canon_windows/` for Shopify and
  WooCommerce: the canonical tables of `entities/commerce.yaml` (the
  columns the model reads, in the order of the contracts) over
  `fixture.sql`, and over `fixture.sql` with `windows.sql`, one CSV file
  a table, with `tests/commerce/tables.sql`, their DDL in standard SQL.
  The questions and their expected rows are in
  `tests/<source>/questions.yaml`. `tests/run_canon.py` loads the files
  into ClickHouse and asks the questions through dactopus-ossie-clickhouse,
  so the model's numbers can be checked without dbt or the platform's raw
  rows; `--engine duckdb` asks them through DuckDB's community extension
  `ossie` instead. Its 0.3.0 does not read the metrics of a dataset
  (apache/ossie#591), so the model does not load there as it is:
  `tests/run_canon.py` loads a copy with them moved to the model's metrics. With that
  copy, 72 of the 95 questions give the same
  numbers, 19 are refused, and 4 differ: it leaves out the rows a
  many-to-one relationship finds no match for (by `products.status`, the
  lines of products the `products` table does not have; by
  `customers.first_order_month`, the guests' orders). `tests/export_canon.py` writes
  the files from a built package, and CI fails when a build differs from
  them.

### Changed

- The distinct counts that pair `source_id` with the counted column
  (`orders.buyer_count`, `product_categories.product_count`,
  `product_brands.product_count`, `sessions.users`,
  `sessions.user_conversion_rate`, `readings.reporting_devices`) join the
  two: `COUNT(DISTINCT source_id || '/' || CAST(customer_id AS VARCHAR))`.
  `COUNT(DISTINCT source_id, customer_id)` is not standard SQL, and DuckDB
  rejects it. The numbers are unchanged.
- The questions of `tests/shopify/check_numbers.py` and
  `tests/woocommerce/check_numbers.py` moved to `questions.yaml`, with
  their derivations as comments; the two scripts read it and need
  `pyyaml` (`uv run` installs it). The questions and their numbers are
  unchanged.
- The example databases and labels in `docs/deployment.md` name what
  the store is, not its platform: databases `main_store`, `outlet_store`,
  `wholesale_store`, labels `usa_store`, `wholesale_store`.
- The unions' views read the tables of the stores, properties and
  networks with the rights of the user who built them
  (`+sql_security: definer`, `+definer: CURRENT_USER`). A user with
  `SELECT` on a union's database reads its model without a grant on the
  databases it adds up, and those stay closed to it. Queries through a
  view go under the builder's row policies on those tables, no longer
  the reader's: this changes the numbers of a deployment whose row
  policies there hide rows from the reader. A union changes on its next
  build
  ([Several stores, properties or networks](docs/deployment.md#several-stores-properties-or-networks)).

## [0.9.0] - 2026-11-02

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. Several stores, properties or networks in one deployment: every
table starts with the label `source_id`, `orders` carries `platform`,
and the unions add up the tables of several databases. Every column has
a declared type, and some types change: an incremental run stops on the
changed schema, and a deployment runs `dbt build --full-refresh` once.
No input table changes.

### Added

- Every table of every package has a first column `source_id`, the
  label of the store, property or network its rows come from: the
  variable `ga4_source_id`, `shopify_source_id`, `woocommerce_source_id`
  or `sensor_community_source_id`, `LowCardinality(String)`. The default
  is the package's name (`shopify`); a label other than 1 to 64 of
  `a-z`, `0-9` and `_` stops the build. A dbt test on every model fails
  on a row of another label, as an incremental run after a new label
  leaves, and names `--full-refresh`. `deployment.yml` maps the role
  `source_id` to the variable, and `tests/check_deployment.py` requires
  it.
- The Ossie models have a field `source_id` in every dataset. It comes
  first in every `primary_key` and on both sides of every relationship,
  and every count of distinct values counts them within a label
  (`orders.buyer_count`, `product_categories.product_count`,
  `product_brands.product_count`, `readings.reporting_devices`,
  `sessions.users`, `sessions.user_conversion_rate`): the tables of
  several stores, each built with its own label, keep their orders and
  customers apart. In one database the label is constant and every
  number stays the same. Its description and synonyms (store, shop;
  property, site; network) let an agent find it, and each model's
  instructions say how to answer over several: for a store, property or
  network the question names or describes, an agent lists the labels and
  takes the one that names it (for a store, also the one store in a
  currency the question names), and asks when none does; a question that
  names none means all of them; identifiers repeat across them, so an
  agent groups by one with its `source_id`; "today" is the date where the
  model is served, while each one's dates are in its own zone. GA4 users
  count within a property and are not matched across properties, and a
  sensor network's silent devices count from its own latest contact.
- `orders` has a column `platform`, `shopify` or `woocommerce`, after
  `currency`, and the commerce model a field `orders.platform`: an agent
  over stores of both platforms finds which store a question about
  "the Shopify store" means, and which platform's report rules apply to
  a store. The unions carry it.
- Unions: `unions/commerce`, `unions/web_analytics` and `unions/iot`, dbt
  projects that add up the tables of several stores, properties or
  networks, each built by its package into a database of its own under
  its own label. A union writes a view of each dataset of the domain's
  Ossie model, `UNION ALL` over the databases of
  `commerce_union_databases`, `web_analytics_union_databases` or
  `iot_union_databases`, with the columns the model reads and their
  types as a dbt contract. A commerce union takes Shopify and
  WooCommerce stores alike. The build stops on a database whose column
  types differ from the contract and on the union's own database among
  those it adds up; its test fails when a label is in two databases.
  `deployment.yml` maps the role `input_databases` to the variable.
  `tests/check_contracts.py` checks the unions' contracts against the
  Ossie models and the packages, that `source_id` comes first in every
  key and relationship of the Ossie models, that each package tests the
  key of each dataset (Sensor.Community's `readings` with
  `sensor_community_unique_key`, which replaces the test
  `readings_one_per_sensor_time_measure`), and that the copies of
  `macros/union.sql` and of each package's `macros/freshness.sql` are
  the same; `tests/check_union.py` checks that each label's answers over
  a union are its database's own.

### Fixed

- WooCommerce: an incremental run over a table whose columns a release
  changed stops before its pre-hooks delete a row. dbt's own check of
  the columns comes after the hooks: the run stopped with `order_lines`
  and `refunds` short of the rows of its window, `refunds` empty on the
  fixture.
- WooCommerce: category and brand names (`line_categories.category`,
  `category_path`, `line_brands.brand` and the same fields of
  `product_categories` and `product_brands`) are decoded from the HTML
  escaping WordPress stores them with: `Home & Garden`, not
  `Home &amp; Garden`. No table changes: the next run rebuilds the
  category and brand tables whole.

### Changed

- CI runs a job only when a file it reads changed (the filters in
  `ci.yml`): a pull request that changes only documentation runs none,
  one that changes one package runs that package's jobs and the unions
  job. The Ossie models are validated together in a job of their own.
  The one check `main` requires is `CI passed`, which fails when a job
  failed or was cancelled; a skipped job does not block a merge.
- CI runs on `ubuntu-24.04`, not `ubuntu-latest`, and keys the uv cache
  by `ci.yml`: before, the key was constant and the cache was never
  refreshed.
- AGENTS.md keeps what an agent applies while writing and is not in
  CONTRIBUTING.md: the rules of `source_id`, contracts and unions, the
  model format, ClickHouse traits, which page a change ships with, and
  the development setup. Layout, scope, the authoring rules and the
  checks before a pull request are read from CONTRIBUTING.md, whose
  canon rule gains the two details only AGENTS.md had: a source that
  has less of a field still provides it when the meaning is the same,
  and no canonical field goes in "for completeness".
- The README is split. Each package's guide (loading, settings, known
  differences from the source's own reports) is `sources/<source>/README.md`;
  what each Ossie model answers and its limits is `docs/<domain>.md`;
  the packages in a dbt project, labels, time zones, serving and unions
  are `docs/deployment.md`; layout, what a source package is, out of
  scope and the authoring rules are in CONTRIBUTING.md. The README keeps
  the overview, one quick start and versioning. Notes on how the
  packages were checked against test stores, and the migration note for
  snapshots loaded before 0.5.1, are gone from the guides: the checked
  numbers are stated, the history is this changelog. The install
  recipes take dactopus-ossie-clickhouse from PyPI.
- The commerce model's instructions: one deployment can hold several
  stores, under their labels, in different currencies. An agent asks
  every amount by `orders.currency`, answers in the one currency or in
  each, and never adds up two; amounts of customers go by
  `customers.source_id`. `orders.currency` and `customers.net_amount`
  say the same. A customer of two stores counts in each.
- README, Known differences from WooCommerce Analytics: buyers in a
  month, where the reports also count a customer with only a refund.
- Every package declares the type of each column it writes, a dbt
  contract in `models/schema.yml`, and a build stops on any other. The
  columns an Ossie model reads come first in each table, with the same
  types in every package that serves the model: the tables of Shopify
  and WooCommerce add up with `UNION ALL`. `tests/check_contracts.py`
  checks it in CI. No value changes; these types do:
  - Amounts are `Decimal(38, 8)` and never NULL: `orders.total`,
    `subtotal`, `discount_total`, `shipping_total`, `tax_total`,
    `refunded_total`, `net_total`; `customers.net_total`; `line_total`
    and `returned_amount` of `order_lines`, `line_categories` and
    `line_brands`; `refunds.refunded_amount`; `sales_events.amount`.
    Shopify's were `Decimal(18, 4)` (`customers.net_total`
    `Decimal(38, 4)`), and Shopify's `order_lines.discount_total`
    follows; WooCommerce's were `Nullable(Decimal(38, 8))`, all but
    `orders.refunded_total`.
  - `orders.customer_id` is `Nullable(Int64)`, `customers.customer_id`
    `Int64`: Shopify's were `Nullable(UInt64)` and `UInt64`,
    WooCommerce's `orders.customer_id` `Int64`.
  - Shopify's quantities are `Int64`: `orders.item_quantity`;
    `quantity` and `current_quantity` of `order_lines`,
    `line_categories` and `line_brands`. They were `UInt32` and
    `UInt64`.
  - WooCommerce's `orders.order_time`, `refunds.refund_time` and
    `sales_events.event_time` are `DateTime('UTC')`, not
    `DateTime64(6, 'UTC')`: WooCommerce keeps whole seconds.
  - Flags are `Bool`: `orders.is_cancelled` and
    `customers.second_order_within_*_days` (`Nullable(Bool)`) of both
    packages, WooCommerce's `orders.in_sales_reports` and `is_direct` of
    `line_categories`, `product_categories` and
    `product_categories_all`. They were `UInt8`.
  - Shopify's `order_lines.title` is `String`, not `Nullable(String)`.

  The columns of every table come in a new order, the model's first.
  With `source_id` (Added), every package runs once with
  `--full-refresh` in place of the next incremental run, which stops.
- GA4: `on_schema_change: fail`, as in the other packages; dbt requires
  it of an incremental model with a contract.
- WooCommerce: an order or refund in another currency without a rate
  the package knows now fails in its model, with a message that names
  the README's Known limits, where before the `not_null` tests on its
  amounts failed.
- The commerce model reads its `Bool` flags alone, without `= 1`
  (`orders.is_cancelled`, `orders.in_sales_reports`,
  `customers.second_order_within_*_days` and the
  `customers.second_order_rate_*_days` metrics, `is_direct` of
  `line_categories` and `product_categories`): Postgres has no operator
  for `Bool = Int`, so the model now translates to engines other than
  ClickHouse. The numbers are the same. `tests/check_contracts.py` fails
  on an expression that compares a `Bool` column with a number.
- The commerce model's instructions state each rule that depends on the
  platform from the field that carries it, with Shopify and WooCommerce
  as examples: which orders the sales reports count
  (`orders.in_sales_reports`), the order date (`orders.order_date`), a
  refund of 0, who a customer is (`customers`), what a category and a
  brand are (`line_categories.category`, `line_brands.brand`). The
  rules are the same.
- The web_analytics model's instructions say when GA4 exports a day:
  once, usually in the afternoon of the following day. The days after
  the latest date with rows have not arrived yet, and an agent says up
  to which date the data reaches instead of reporting them as days
  without visits; the latest date is a whole day, and a low count there
  is not a partial export
  ([#48](https://github.com/Dactopus/dactopus-data-models/issues/48)).
  `docs/web_analytics.md` says the same.
- `ROADMAP.md`: Magento (Adobe Commerce) under Exploring, a store whose
  MySQL database reaches ClickHouse by CDC, as WooCommerce's does.

## [0.8.0] - 2026-10-30

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. Customers for Shopify and
WooCommerce. `orders` gains columns, and the WooCommerce
`orders.customer_id` changes type: an incremental run stops on the
changed schema, and a deployment runs `dbt build --full-refresh`. No
input table changes.

### Added

- `commerce.yaml`: `customers`, one row per customer with an order the
  store's report of new and returning customers counts, with
  `first_order_date`, `first_order_month` (the cohort),
  `last_order_date`, `number_of_orders` and `net_total`, what the
  orders earned after refunds and cancellations (at WooCommerce, orders
  on hold included, as the Customers report's total spend). Metrics
  `customer_count`, `net_amount` and `average_customer_value`. `orders`
  joins it on `customer_id`, so orders break down by cohort. A customer
  record without such an order has no row, and the table holds no
  email, name or address. Both packages build it from `orders` on every
  run.
- Retention windows: `customers.second_order_within_30_days`,
  `_60_days`, `_90_days` and `_365_days`, whether the second order came
  within that many days of the first, and the metrics
  `second_order_rate_30_days` to `second_order_rate_365_days`, the
  share among customers whose window is over. A window stays empty
  until its last day is before the day of the last load of orders
  (`loaded_at` at Shopify, `synced_at` at WooCommerce, in the store's
  time zone): it moves only when orders are loaded, so an
  incremental run over unchanged input changes nothing.
- `orders.days_since_previous_order` and `months_since_first_order`
  (-1 on the first order, then calendar months, as Shopify's
  `months_since_first_purchase`), between the dates the customer's
  sequence goes by: `processed_at` at Shopify, the date placed at
  WooCommerce, in the store's time zone. The metric
  `orders.average_days_between_orders` averages the first.
- Singular test `orders_numbered_in_sequence` in both packages: each
  customer's orders are numbered 1 to n.
- Fixture cases for the customers and the windows
  (`tests/<source>/windows.sql`, `check_numbers.py --windows`), and CI
  steps that feed WooCommerce guest orders in parts and compare
  `customers` with a full refresh.

### Changed

- Shopify: cancelled orders take their place in the customer's sequence
  (`customer_order_number`, `new_vs_repeat`), as Shopify's report of new
  and returning customers counts them: on the development store a
  customer's only order, cancelled, is New, and the next one Returning.
  Over the fixture `orders.repeat_order_share` goes from 5/7 to 6/9.
- WooCommerce: every order has a `customer_id`, the customer WooCommerce
  Analytics counts. A guest's order belongs to the account that has an
  order billed to the same email, in any letter case (the smallest such
  account where there are several); else to the guest, one per email,
  numbered by the smallest id of their orders with a minus sign
  (`-112`); a guest's order without an email is a customer of its own.
  Guests are counted and numbered.
- `orders.customers` is renamed `orders.buyer_count`, no longer named
  like a dataset. This breaks saved questions and dashboards that ask
  for the old name.
- `orders.repeat_order_share`, a share of orders, gives up the synonyms
  "repeat purchase rate" and "repeat rate": they usually ask about
  customers and go to the windows' rates. An agent asked for a repeat
  purchase rate now answers with a window and names it.
- The README's known differences from Shopify's reports and from
  WooCommerce Analytics follow the new numbering. On the development
  store Shopify's customers, new and returning by month, each customer's
  total sales and orders, and orders by `months_since_first_purchase`
  equal the reports'. At WooCommerce the customers differ from Analytics
  where an account's order is billed to another email: the model joins
  that email's guest orders to the account. The README's commerce
  section lists the customers' metrics.
- `ROADMAP.md`: Customers is done and leaves Next. Discount codes, which
  code brought the revenue, is planned after it, under Later.

## [0.7.2] - 2026-10-27

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The Shopify input gains a
column, and `refunds` and `sales_events` need the rebuild the first entry
describes; every other table builds the same as in 0.7.1.

### Fixed

- Shopify: a refund is dated by its `processedAt`, the date Shopify's
  sales reports count it on, instead of its `createdAt`
  ([#45](https://github.com/Dactopus/dactopus-data-models/issues/45)).
  The two are equal for a refund made in the admin. A refund imported
  with a past `processedAt`, as a store that moves its history to
  Shopify records its returns, counted on the day of the import in
  `refunds.refund_date` and `sales_events.event_date`, and its month's
  net sales were too high. The `refunds` input table has a new column,
  `processed_at`, which a loader must deliver; the README's export
  query reads it. A deployment adds it to the input, giving the refunds
  already loaded their `created_at`:

  ```sql
  ALTER TABLE shopify_raw.refunds ADD COLUMN processed_at DateTime('UTC') DEFAULT created_at AFTER created_at;
  ALTER TABLE shopify_raw.refunds MATERIALIZE COLUMN processed_at SETTINGS mutations_sync = 1;
  ALTER TABLE shopify_raw.refunds MODIFY COLUMN processed_at REMOVE DEFAULT;
  ```

  A store with imported refunds then exports its orders again from
  before the first import, so that those refunds arrive with their
  `processedAt`. Last, `dbt build --full-refresh --select refunds+`
  rebuilds `refunds` and `sales_events`: an incremental run keeps the
  old dates of the refunds it does not reread, with no error.
- The descriptions of `refunds.refund_date` and `refund_time` say which
  date they hold: the date the store's reports date the refund by, at
  Shopify the date it was processed, for an imported refund its past
  date and not the day it was recorded, as `order_date` says for orders.
- The Shopify and WooCommerce packages set `join_use_nulls = 0` in their
  queries. Their LEFT JOINs count on a missing match giving 0 (an order
  without gift cards, a refund without lines); a server or profile that
  sets it to 1 gave NULL totals and the build failed on
  `sales_events.amount`. `tests/profiles.yml` sets 1, so CI builds
  against the setting the packages must not depend on.

## [0.7.1] - 2026-10-27

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.12.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. No table changes, no rebuild
is needed.

### Added

- `commerce.yaml`: order lines reach the catalog
  (`order_lines_to_products`), so sales break down by the product's
  current status, such as the sales of products archived since
  ([#43](https://github.com/Dactopus/dactopus-data-models/issues/43)).
  A line of a product no longer in the catalog (deleted, or in the
  trash at WooCommerce) has an empty status. Sales by category and brand
  still come from `line_categories` and `line_brands` alone:
  `product_categories` and `product_brands` declare no key, so
  dactopus-ossie-clickhouse refuses a filter on them for a metric of
  order lines, which would leave out products in the trash and differ
  from the store's category report. The model's instructions send
  products that sold to `products.last_sold_date` and sales by product
  to `order_lines.title`: products filtered by order lines would count
  cancelled orders, and a product no longer in the catalog has no
  title in `products`.

### Changed

- dactopus-ossie-clickhouse 0.12.0 instead of 0.10.1 in CI, the README
  and CONTRIBUTING. The models load and answer as before: none repeats a
  key, which 0.11.0 refuses; none writes `SPLIT_PART`, which 0.11.0
  returns as NULL for a NULL string; none writes `CONTAINS` or
  `EXTRACT(MILLISECOND ...)`, which 0.12.0 sends to ClickHouse in another
  form.
- WooCommerce: `products` joins the orders by merge instead of a hash
  table to find each product's last sale. On 4 million orders the run's
  peak falls from between 250 and 380 MB to between 60 and 70 MB, in
  the same time, and the numbers do not change
  ([#42](https://github.com/Dactopus/dactopus-data-models/issues/42)).
  No rebuild is needed.

## [0.7.0] - 2026-10-26

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.10.1,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9.

Products for Shopify and WooCommerce: categories, brands and the
catalog. Both packages read new input tables, and `order_lines` gains
columns: a deployment loads the new input and runs
`dbt build --full-refresh`.

### Added

- `commerce.yaml`: `line_categories` and `line_brands`, each order line
  once per category or brand of its product, with model metrics for
  units, revenue, returns and net revenue by category (`category_*`)
  and by brand (`brand_*`). A category is the product type at Shopify
  and a product category at WooCommerce, where categories nest
  (`category_path`, `is_direct`); a brand is the vendor at Shopify and a
  product brand at WooCommerce. Both are the product's current ones, as
  in the stores' reports. The category metrics count a line in its
  product's own categories, as WooCommerce Analytics' Categories report
  does; one category with its subcategories is the order lines' metrics
  filtered by its path.
- `commerce.yaml`: `products`, the catalog, sold or not, with its status
  (active, draft, archived) and the date of the last sale, and
  `product_categories` and `product_brands`, each with
  `product_count`. Gift cards, deleted products and WooCommerce's trash
  are not in the catalog.
- `order_lines.returned_quantity` and `returned_amount`, what refunds
  and, at Shopify, cancellations took back, without tax; the model
  metrics `items_returned`, `line_returned_amount` and
  `line_net_revenue` count them on the date of the order.
- Shopify input `products`, a log of versions like `orders`; a deleted
  product comes as a version with `deleted_at`. `export_shopify.py` in
  the README exports the products and finds deletions in the store's
  events.
- WooCommerce input `wp_posts` (without its text columns), `wp_terms`,
  `wp_term_taxonomy` and `wp_term_relationships`, in two more PeerDB
  mirrors (README, Your store, step 3).
- Hand-written products, categories and brands on the fixtures' lines,
  and the numbers the model must answer over them: Shopify 31 questions,
  WooCommerce 35.

### Changed

- The Shopify `order_lines` rereads the orders whose refunds or refund
  lines were loaded since the last run, for the returned columns.
- `orders.average_order_value` says that, filtered by a category, it
  counts each order whole, as WooCommerce Analytics' filter does, while
  Shopify's report filtered by product type counts only that type's
  lines.
- The README's known differences from Shopify's reports and from
  WooCommerce Analytics cover products, checked on a development store
  and on a local store: WooCommerce's Categories and Products reports
  also count unpaid orders on hold.
- `ROADMAP.md`: Products is done; GA4 items are about what only the
  site sees.
- `AGENTS.md`: a source that has less of a field still provides it when
  the meaning is the same.

## [0.6.1] - 2026-10-25

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.10.1,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. Metric names change; no
table or column changes, no rebuild is needed.

### Changed

- A metric that reads one dataset is declared on it
  (`datasets[].metrics`, the Ossie spec's "Metric Scoping",
  apache/ossie#591), and a question names it `dataset.metric`:
  `orders.revenue`, `sessions.session_count`, `devices.device_count`.
  The name says whose rows a metric counts, in `list_model` too, and
  `describe_object` of a dataset lists its metrics. The five commerce
  metrics that read order lines or refunds together with
  `orders.in_sales_reports` stay on the model under their own names. A
  metric named like a field or a dataset is renamed, since a dataset's
  fields and metrics share one set of names.
  This breaks saved questions and dashboards that ask for the old names,
  and result columns are named `dataset.metric` too; update them:

  | Old | New |
  | --- | --- |
  | `orders` | `orders.order_count` |
  | `all_orders`, `all_orders_total`, `revenue`, `refunded_amount`, `refund_rate`, `average_order_value`, `items_per_order`, `customers`, `repeat_order_share` | the same name on `orders`: `orders.revenue` |
  | `discount_total` | `orders.discount_amount` |
  | `shipping_total` | `orders.shipping_amount` |
  | `tax_total` | `orders.tax_amount` |
  | `net_revenue` | `sales_events.net_revenue` |
  | `refunds` | `refund_count` |
  | `items_sold`, `items_net`, `line_revenue`, `refunds_total` | unchanged |
  | `sessions` | `sessions.session_count` |
  | `engaged_sessions`, `engagement_rate`, `users`, `session_conversion_rate`, `user_conversion_rate` | the same name on `sessions` |
  | `page_views` | `sessions.page_view_count` |
  | `purchases` | `purchases.purchase_count` |
  | `gross_purchase_revenue`, `gross_purchase_revenue_usd`, `average_gross_purchase_revenue` | the same name on `purchases` |
  | `events` | `events.event_count` |
  | `reading_count`, `avg_value`, `min_value`, `max_value`, `reporting_devices`, `last_reading_time` | the same name on `readings` |
  | `device_count`, `last_contact_time`, `minutes_since_last_contact` | the same name on `devices` |

  Numbers are unchanged, and so are the fields, among them
  `orders.discount_total`, `orders.shipping_total`, `orders.tax_total`
  and `sessions.page_views`. A count of a dataset's rows is `COUNT(*)`,
  where it counted a key that is never NULL.
- dactopus-ossie-clickhouse 0.10.1 instead of 0.10.0. A field asked for
  as a metric, such as `refunds.refunded_amount`, or an old metric name
  that is a field now, such as `tax_total`, gets the metrics that add
  it up (`refunds_total`, `orders.tax_amount`) instead of names close in
  spelling
  ([dactopus-ossie-clickhouse#66](https://github.com/Dactopus/dactopus-ossie-clickhouse/issues/66)).
  `search_model` lists matching metrics apart from fields, so a broad
  word such as "refund" no longer leaves `refunds_total` out.

## [0.6.0] - 2026-10-23

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.10.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. Every package ships a
`deployment.yml`
([#36](https://github.com/Dactopus/dactopus-data-models/issues/36)).
The view `devices` has the same sites as in 0.5.3; `devices_archive`
gains coordinates for sites in the snapshots. A plain `dbt build`
updates both; no `--full-refresh`.

### Added

- `deployment.yml` in every package: what a deployment sets and reads,
  for the tools that deploy the packages without reading their SQL. It
  names the Ossie model the package's tables serve, the dbt variables
  for the input database and the time zone by role, and the tables a
  deployment counts rows per day in, with the Date column, the time
  column that date is the day of, and whether a day without rows is a
  gap. `tests/check_deployment.py` holds each file to its package and
  built tables; with `--time-zone` it counts the rows whose date is not
  the day of their time in the zone, which finds a Shopify or
  WooCommerce table built in two zones: an incremental run after the
  zone variable changed rebuilds only the orders and refunds loaded
  since the last run, and no dbt test fails
  ([#36](https://github.com/Dactopus/dactopus-data-models/issues/36)).

### Changed

- The iot model sends "latest data", "last update" and "data up to" to
  `last_contact_time`, which `last_reading_time` had for the last two.
  An agent asked what the data is up to answered with the latest
  reading, hours older than the latest contact while the snapshots run
  ([#30](https://github.com/Dactopus/dactopus-data-models/issues/30)).
- `devices_archive` keeps every site's coordinates from its latest row
  in the archive and no longer reads `locations`. `devices` still
  prefers the snapshot's coordinates; a site that leaves the snapshots,
  as when `locations` is reloaded for other countries, keeps its
  coordinates; in 0.5.3 they were NULL until the next run. The view
  `devices` reads `locations` and `devices_archive` once per question
  instead of twice
  ([#29](https://github.com/Dactopus/dactopus-data-models/issues/29)).
- dactopus-ossie-clickhouse 0.10.0 instead of 0.9.5. Its `query` tool
  says when `limit` cut off rows (`truncated`), and an agent is told to
  draw no conclusion about the whole set then; before, 100 rows came
  back with nothing to say they might not be all. A failure to connect
  is one line that names what to check. Keys and relationships now name
  fields of their dataset, as the Ossie spec says; the models here name
  their key fields after their columns and load unchanged.

## [0.5.3] - 2026-10-22

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.9.5,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The GA4 and commerce models
can be served together
([#28](https://github.com/Dactopus/dactopus-data-models/issues/28)).
No table or column changes; no rebuild is needed.

### Changed

- The GA4 model's revenue metrics are renamed after GA4's own terms, so
  that they no longer clash with the commerce model's `revenue` and
  `average_order_value`, which the executor refused to serve in one
  model. This breaks saved questions and dashboards that ask for the old
  names; update them:

  | Old | New |
  | --- | --- |
  | `revenue` | `gross_purchase_revenue` |
  | `revenue_usd` | `gross_purchase_revenue_usd` |
  | `average_order_value` | `average_gross_purchase_revenue` |

  The names say gross because refunds are not subtracted: GA4's
  "Purchase revenue" subtracts the refunds the site sent, "Gross
  purchase revenue" does not, and the model reads purchase events only.
  Expressions and numbers are unchanged, and so are the fields
  (`purchases.revenue`, `purchases.revenue_usd`).
- Store terms (sales, orders, number of orders, transactions, income,
  turnover, AOV, average order, average check) leave the GA4 metrics'
  and datasets' synonyms, so an agent served both models finds the
  store's figures for them. The GA4 model's instructions say so too.
- CI validates every model together, so a name defined in two files
  fails the build.

## [0.5.2] - 2026-10-22

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.9.5,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The packages ship no dbt
profile ([#25](https://github.com/Dactopus/dactopus-data-models/issues/25)).
Every package builds the same tables as in 0.5.1; no rebuild is needed.

### Removed

- `profiles.yml` from every package. How to reach ClickHouse is up to
  whoever runs a package, and the shipped profile had no room for a
  setting it lacked, such as `secure` for TLS. A project that installs
  the packages through `packages.yml` and the runner use profiles of
  their own. A package run by hand with
  `--profiles-dir sources/<package>` now needs a profile named
  `dactopus` in `~/.dbt/profiles.yml` or a directory given with
  `--profiles-dir`: the README's Quick start has one, the same as the
  removed profile.

### Changed

- CI and the checks build with `tests/profiles.yml`.
- dactopus-ossie-clickhouse 0.9.5 instead of 0.9.4. It connects over TLS
  whenever the URL is `https://`, where 0.9.4 did so only on ports 443
  and 8443 and otherwise sent the user and password in the clear; an
  `http://` URL on those ports no longer gets TLS. The README's Quick
  start says to write `https://` over TLS.

## [0.5.1] - 2026-10-22

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.9.4,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9. The Sensor.Community package
answers silence from the API's snapshots
([#26](https://github.com/Dactopus/dactopus-data-models/issues/26)).
The README serves the commerce and GA4 models in the zone their dates
were built in, so that "today" is the store's or the property's date
([#31](https://github.com/Dactopus/dactopus-data-models/issues/31)).
GA4, Shopify and WooCommerce build the same tables as in 0.5.0. No
rebuild is needed: a `dbt build` replaces the table `devices` with a
view, from 0.5.0 on both dbt versions.

### Added

- `devices.last_contact_at` in `entities/iot.yaml`: the later of a
  site's latest report in the API's snapshots, from a sensor of any
  type, and its latest reading. Metrics `last_contact_time`, the latest
  contact with any site, and `minutes_since_last_contact`, its age by
  the database's clock.
- Hand-written rows of a snapshot loaded after the last build, and 3
  more numbers the model must answer over them, 17 in all.

### Changed

- Silence is measured from the latest contact in the data, within
  minutes of now while the snapshots run, instead of from the latest
  reading, hours old. The model tells agents to name that time and its
  age. "Silent", "offline" and "last seen" now lead to `last_contact_at`;
  `last_reading_at` and `last_reading_time` keep their numbers.
- `devices` is a view over the snapshots and the new table
  `devices_archive`, which the build writes from the readings: a
  snapshot reaches the model as soon as it is loaded, with a site's
  country and indoor flag, without a build.
- The snapshot query (README, Quick start, Sensor.Community, step 2)
  keeps one row per sensor, its latest record. Snapshots loaded by the
  query of 0.5.0 can show a sensor's last contact up to five minutes
  early (README, Limits of the iot model).
- dactopus-ossie-clickhouse 0.9.4 instead of 0.9.1. It shows times with
  their offset (`2026-10-19 12:29:50+00:00`), and its "today" is the
  date in the zone it is served in, UTC by default, not in the server's
  zone; so is a time written without an offset, as a plain string or a
  `TIMESTAMP` literal. The README serves the GA4 and commerce models with
  `--time-zone` set to the zone the package was built in, so a question
  about today counts the store's date (Use in your dbt project). CI
  validates and checks the Shopify and WooCommerce models with that
  zone set, and each asks two more questions whose answers depend on
  it, 20 in all.

## [0.5.0] - 2026-10-21

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.9.1,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. A new domain and its package; GA4, Shopify and WooCommerce
build the same tables as in 0.4.1, and no rebuild is needed.

### Added

- Ossie model `entities/iot.yaml`, a reference domain built from one
  public dataset: `readings` (one row per sensor, time and measure:
  PM10, PM2.5, temperature, humidity, pressure) and `devices` (one row
  per site, with its country, indoor flag and latest reading), one
  relationship and 7 metrics. Every time is UTC. The model tells agents
  to read value metrics one measure at a time, to say when an average
  across devices includes indoor ones, and to measure silence from the
  latest reading in the data.
- Sensor.Community package `sources/sensor_community` over the
  archive's daily files and the API's snapshots, loaded into the input
  tables `sources/sensor_community/input.sql` by the README's recipe.
  Of two rows for one sensor and time it keeps the one with the lower
  values; `nan` is no reading, and a pressure sent in hPa becomes Pa.
  `readings` is incremental: a run rereads whole sensor-days loaded
  since the last one (`sensor_community_lookback_days`, default 3);
  `devices` is rebuilt whole. Structural checks and freshness of both
  inputs. Installs from a git tag with
  `subdirectory: sources/sensor_community`; dbt v2 freshness needs the
  package in the `dispatch` setting (README).
- Hand-written Sensor.Community rows and the 14 numbers the model must
  answer over them (`tests/sensor_community`), checked in CI on both dbt
  versions, on the incremental and the full build.

### Changed

- CI: a new push to a pull request cancels the run on its previous push;
  each run on `main` finishes.
- The README, CONTRIBUTING.md and CI install dactopus-ossie-clickhouse
  0.9.1 instead of 0.8.0. It counts devices filtered by their readings
  (README, Limits of the iot model). The models are unchanged, and
  their questions get the same SQL apart from the setting
  `transform_null_in = 0`.

## [0.4.1] - 2026-10-15

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.8.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. Every package builds the same tables as in 0.4.0, row for row;
no rebuild is needed.

### Fixed

- The Shopify package's memory grew with the shop's history: on a
  ClickHouse server limited to 4 GB, the first build of a shop with 2
  million orders ran out of memory
  ([#8](https://github.com/Dactopus/dactopus-data-models/issues/8)).
  Such a shop now builds in at most 1.1 GB per query, and a shop of 8
  million orders in 2.7 GB; an incremental run of `orders` needs 0.2 GB
  instead of 1.7 GB. A full build takes about twice as long. Measurements:
  [README](sources/shopify/README.md#known-differences-from-shopifys-reports). The saving
  needs the input tables' sorting keys of `input.sql`; with other keys
  the package builds the same rows at the old memory. The suggested
  `ReplacingMergeTree` key of `refunds` is now `(order_id, id)`.

## [0.4.0] - 2026-10-15

Ossie schema `0.2.0.dev0`. Tested with dactopus-ossie-clickhouse 0.8.0,
dbt v2 (`dbt-oss` 2.0.8) and dbt v1 (`dbt-core` 1.11 with
`dbt-clickhouse` 1.10) on ClickHouse 26.9, the WooCommerce package also
on 26.7. Two changes can stop a WooCommerce deployment until it meets
them (Changed): ClickHouse 26.7 or later, and `ALTER MODIFY COMMENT` on
`refunds` for its dbt user. No rebuild is needed. The numbers are the
same except `customer_order_number` (with `new_vs_repeat` and
`repeat_order_share`) for a customer that
[#17](https://github.com/Dactopus/dactopus-data-models/issues/17) left
stale: a full refresh corrects it at once, otherwise the next change to
one of the customer's orders does. GA4 and Shopify build the same tables
as in 0.3.0.

### Changed

- The WooCommerce package needs ClickHouse 26.7 or later: its models
  compute each shared subquery once (`WITH ... AS MATERIALIZED`, Fixed
  below), which ClickHouse 26.3 to 26.6 fail on. CI runs the package on
  26.7 and 26.9.
- The dbt user of a WooCommerce deployment needs `ALTER MODIFY COMMENT`
  on `refunds` (part of `ALTER TABLE`, separate from `ALTER DELETE`):
  each run keeps the next window's start in that table's comment (Fixed
  below). A role granted `ALTER DELETE` without it fails after the
  upgrade.
- The README, CONTRIBUTING.md and CI install dactopus-ossie-clickhouse
  0.8.0 instead of 0.7.0. It reads a model split over several files and
  reports a misspelt `CLICKHOUSE` entry as a model problem. The models
  are unchanged and pass the same checks on 0.8.0.

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
  is lost.
- WooCommerce's models ran their changed-orders subquery again at every
  reference: with two orders changed out of 320,000, `order_lines` read
  123 million rows (2.5 GB). Each shared subquery now runs once
  (`WITH ... AS MATERIALIZED`): 10 million rows (160 MB), 1.1 s down to
  0.3 s; `orders` 670 MB down to 375 MB and 1.7 s down to 0.65 s. A full
  rebuild of `order_lines` takes 0.8 s instead of 4.2 s and 0.75 GB of
  memory instead of 1.2 GB. The rows are the same.
- WooCommerce: an order moved to another customer and then trashed or
  deleted in one sync window, after the input had merged away the
  version that named the first customer, left that customer's later
  orders with their old `customer_order_number` until a full refresh
  ([#17](https://github.com/Dactopus/dactopus-data-models/issues/17)).
  The `orders` pre-hook now keeps the window's orders and the customer
  each one had in `orders__changed` before it deletes anything, the
  model reads them there, and a post-hook drops the table; after a run
  that fails, the next one keeps the table's rows too. The pre-hook
  also computes the window's orders once instead of twice: on 320,000
  synthetic orders an incremental run of `orders` read 9 to 10 million
  rows (410 to 450 MB) instead of 36 to 38 million (850 to 870 MB), 1.2
  to 1.9 s instead of 2 to 2.5 s of query time. No rebuild is needed. A
  customer whose numbers went stale before the upgrade gets them right
  when one of their orders next changes, or with a full refresh.
- WooCommerce: when CDC delivered a version of a row twice, the copies
  stamped with different sync times, a model took either copy, so an
  order's `synced_at`, and where the next incremental window started,
  could differ between runs over the same input. The latest sync is now
  taken. Numbers were not affected.

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

[Unreleased]: https://github.com/Dactopus/dactopus-data-models/compare/v0.11.2...HEAD
[0.11.2]: https://github.com/Dactopus/dactopus-data-models/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/Dactopus/dactopus-data-models/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/Dactopus/dactopus-data-models/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/Dactopus/dactopus-data-models/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Dactopus/dactopus-data-models/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.1.0
