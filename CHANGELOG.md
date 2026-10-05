# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/) as the README's
[Versioning](README.md#versioning) section applies them. Every release
names the Ossie schema version its models carry.

## [Unreleased]

### Added

- A diagram of how the GA4 package works with GA4, ClickHouse, BI tools
  and AI agents: an image in the README and an interactive page on GitHub
  Pages (`docs/`).
- README: the metrics the GA4 model answers, and the known differences
  from the GA4 interface.
- `ROADMAP.md`: what comes next, without dates. The README links to it
  instead of listing planned sources as if they existed.

### Fixed

- README: the opening no longer lists orders, line items and customers as
  available; the Quick start names ossie-clickhouse with its MCP server
  among the requirements. Its example of how sources differ no longer
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

[Unreleased]: https://github.com/Dactopus/dactopus-data-models/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.1.0
