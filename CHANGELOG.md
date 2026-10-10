# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/) as the README's
[Versioning](README.md#versioning) section applies them. Every release
names the Ossie schema version its models carry.

## [Unreleased]

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

[Unreleased]: https://github.com/Dactopus/dactopus-data-models/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Dactopus/dactopus-data-models/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.1.0
