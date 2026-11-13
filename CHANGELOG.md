# Changelog

The format follows [Common Changelog](https://common-changelog.org);
versions follow [Semantic Versioning](https://semver.org) as the
README's [Versioning](README.md#versioning) section applies them. What a
deployment does to move to a release: [UPGRADING.md](UPGRADING.md).

## [0.13.0] - 2026-11-11

_Moving to it takes dactopus-ossie-clickhouse 0.15.0 or newer and one `dbt build` ([Upgrading](UPGRADING.md#0130))._

### Changed

- **Breaking:** Move the models to Ossie schema `0.3.0.dev0`, which needs dactopus-ossie-clickhouse 0.15.0 or newer ([#78](https://github.com/Dactopus/dactopus-data-models/pull/78))
- **Breaking:** Require ClickHouse 26.8 or newer for the WooCommerce package ([#79](https://github.com/Dactopus/dactopus-data-models/pull/79))

### Added

- Add `order_discount_codes`, each order with each discount code or coupon used on it, and five metrics by code ([#77](https://github.com/Dactopus/dactopus-data-models/pull/77))
- Add `orders.order_weekday`, the day of the week of the order's date ([#77](https://github.com/Dactopus/dactopus-data-models/pull/77))
- Add `evals/`: questions an owner asks an AI agent over each model, with expected answers and a grader ([#79](https://github.com/Dactopus/dactopus-data-models/pull/79))

## [0.12.2] - 2026-11-09

_The GA4 and Sensor.Community packages need a grant and one `dbt build --full-refresh` ([Upgrading](UPGRADING.md#0122))._

### Changed

- **Breaking:** Stop an incremental run of the GA4 and Sensor.Community packages whose label differs from the one their tables were built with ([#74](https://github.com/Dactopus/dactopus-data-models/pull/74))
- Run one settings guard, `macros/settings.sql`, in every package in place of the Shopify and WooCommerce macros ([#74](https://github.com/Dactopus/dactopus-data-models/pull/74))
- Read a variable a later release starts to guard as its default from a table built before ([#74](https://github.com/Dactopus/dactopus-data-models/pull/74))

### Added

- Add `meta.guarded_vars` and `meta.free_vars` to each package's `dbt_project.yml`, the variables a run may not and may change ([#74](https://github.com/Dactopus/dactopus-data-models/pull/74))
- Document the phrase `was not built with the settings of this run` as the one a deployment tool can tell the guard's stop by ([#74](https://github.com/Dactopus/dactopus-data-models/pull/74))

## [0.12.1] - 2026-11-07

### Fixed

- Stop the commerce instructions saying that a store missing from a result has a zero ratio or average ([#73](https://github.com/Dactopus/dactopus-data-models/pull/73))

## [0.12.0] - 2026-11-04

_Moving to it takes a grant, one `dbt build --full-refresh` and new metric names ([Upgrading](UPGRADING.md#0120))._

### Changed

- **Breaking:** Put the 18 commerce metrics of order lines, categories, brands and refunds on their datasets, as `order_lines.line_revenue` ([#69](https://github.com/Dactopus/dactopus-data-models/pull/69))
- **Breaking:** Require `ALTER MODIFY COMMENT` on `orders`, `order_lines` and `refunds` of the Shopify and WooCommerce packages ([#71](https://github.com/Dactopus/dactopus-data-models/pull/71))

### Added

- **Breaking:** Stop an incremental run of the Shopify and WooCommerce packages whose settings differ from those the tables were built with ([#71](https://github.com/Dactopus/dactopus-data-models/pull/71))
- **Breaking:** Add `in_sales_reports`, the flag of the order, to `order_lines`, `line_categories`, `line_brands` and `refunds` ([#69](https://github.com/Dactopus/dactopus-data-models/pull/69))
- Add the `category_tree_*` metrics of `line_categories` and `product_categories`, a category with its subcategories, each line or product once ([#70](https://github.com/Dactopus/dactopus-data-models/pull/70))
- Add tests that no line or refund has another `in_sales_reports` than its order ([#69](https://github.com/Dactopus/dactopus-data-models/pull/69))

### Fixed

- Return NULL from `orders.refund_rate`, `average_order_value`, `items_per_order` and `repeat_order_share` when no order counts, instead of dividing by zero ([#69](https://github.com/Dactopus/dactopus-data-models/pull/69))
- Say in the commerce instructions that the metrics of `customers` count the orders of the store's customers report ([#70](https://github.com/Dactopus/dactopus-data-models/pull/70))

## [0.11.2] - 2026-11-04

### Changed

- Keep only the rules across datasets in the instructions of the three models, within 2,300 characters ([#68](https://github.com/Dactopus/dactopus-data-models/pull/68))

## [0.11.1] - 2026-11-04

### Changed

- Name the source packages in the model descriptions without repository paths ([#66](https://github.com/Dactopus/dactopus-data-models/pull/66))

## [0.11.0] - 2026-11-04

_Serving the models takes dactopus-ossie-clickhouse 0.11.0 or newer ([Upgrading](UPGRADING.md#0110))._

### Changed

- **Breaking:** Write expressions in the `sql` form instead of `dialects`, which needs dactopus-ossie-clickhouse 0.11.0 or newer ([#65](https://github.com/Dactopus/dactopus-data-models/pull/65))

## [0.10.0] - 2026-11-03

_A union's views read with the rights of the user who built them ([Upgrading](UPGRADING.md#0100))._

### Changed

- **Breaking:** Read the tables a union adds up with the rights and row policies of the user who built it ([#64](https://github.com/Dactopus/dactopus-data-models/pull/64))
- Count distinct values with their label as `source_id || '/' || CAST(... AS VARCHAR)`, which engines other than ClickHouse accept ([#63](https://github.com/Dactopus/dactopus-data-models/pull/63))

### Added

- Add `zone` to `deployment.yml`, the zone of a package's days when the package fixes it, and check it in `tests/check_deployment.py` ([#62](https://github.com/Dactopus/dactopus-data-models/pull/62))
- Add the canonical tables of the commerce fixtures and `tests/run_canon.py`, which asks the model's questions over them without dbt ([#63](https://github.com/Dactopus/dactopus-data-models/pull/63))

## [0.9.0] - 2026-11-02

_Every package needs one `dbt build --full-refresh` ([Upgrading](UPGRADING.md#090))._

### Changed

- **Breaking:** Declare the type of every column in a dbt contract: amounts `Decimal(38, 8)`, customer keys and quantities `Int64`, flags `Bool`, the model's columns first ([#51](https://github.com/Dactopus/dactopus-data-models/pull/51))
- Set `on_schema_change: fail` in the GA4 package, as in the others ([#51](https://github.com/Dactopus/dactopus-data-models/pull/51))
- Fail a WooCommerce model on an amount in a currency without a known rate, where its `not_null` tests failed ([#51](https://github.com/Dactopus/dactopus-data-models/pull/51))
- Read `Bool` flags alone in the commerce model, which then translates to engines other than ClickHouse ([#58](https://github.com/Dactopus/dactopus-data-models/pull/58))
- State each rule of the commerce instructions that depends on the platform from the field that carries it ([#58](https://github.com/Dactopus/dactopus-data-models/pull/58))
- Tell an agent when GA4 exports a day, so that it names the latest date instead of reporting days without visits ([#58](https://github.com/Dactopus/dactopus-data-models/pull/58))
- Tell an agent to give amounts per currency across stores ([#52](https://github.com/Dactopus/dactopus-data-models/pull/52))
- Split the README into package guides, model pages and `docs/deployment.md` ([#53](https://github.com/Dactopus/dactopus-data-models/pull/53))

### Added

- **Breaking:** Add the label `source_id` as the first column of every table and to every key and relationship of the Ossie models ([#51](https://github.com/Dactopus/dactopus-data-models/pull/51))
- **Breaking:** Add `orders.platform`, `shopify` or `woocommerce` ([#56](https://github.com/Dactopus/dactopus-data-models/pull/56))
- Add the unions `unions/commerce`, `unions/web_analytics` and `unions/iot`, views that add up the tables of several databases ([#52](https://github.com/Dactopus/dactopus-data-models/pull/52))

### Fixed

- Stop a WooCommerce incremental run over changed columns before its pre-hooks delete a row ([#51](https://github.com/Dactopus/dactopus-data-models/pull/51))
- Decode the HTML entities in WooCommerce category and brand names ([#49](https://github.com/Dactopus/dactopus-data-models/pull/49))

## [0.8.0] - 2026-10-30

_Shopify and WooCommerce need one `dbt build --full-refresh`, and a metric is renamed ([Upgrading](UPGRADING.md#080))._

### Changed

- **Breaking:** Rename `orders.customers` to `orders.buyer_count` ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- **Breaking:** Number cancelled Shopify orders in the customer's sequence, as Shopify's report of new and returning customers does ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- **Breaking:** Give every WooCommerce order the `customer_id` WooCommerce Analytics counts, a guest's by email ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- Drop the synonyms "repeat purchase rate" and "repeat rate" from `orders.repeat_order_share` ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))

### Added

- **Breaking:** Add `orders.days_since_previous_order`, `months_since_first_order` and the metric `orders.average_days_between_orders` ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- Add `customers`, one row per customer the store's report counts, with their first and last order and net total ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- Add the retention windows `customers.second_order_within_*_days` and their `second_order_rate_*_days` metrics ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))
- Add the test `orders_numbered_in_sequence` to both packages ([#47](https://github.com/Dactopus/dactopus-data-models/pull/47))

## [0.7.2] - 2026-10-27

_The Shopify input gains a column, and `refunds` needs a rebuild ([Upgrading](UPGRADING.md#072))._

### Fixed

- **Breaking:** Date a Shopify refund by its `processedAt`, read from the new input column `processed_at` ([#46](https://github.com/Dactopus/dactopus-data-models/pull/46))
- Set `join_use_nulls = 0` in the Shopify and WooCommerce packages, whose builds failed on a server that sets 1 ([#46](https://github.com/Dactopus/dactopus-data-models/pull/46))
- Say in `refunds.refund_date` and `refund_time` which date they hold ([#46](https://github.com/Dactopus/dactopus-data-models/pull/46))

## [0.7.1] - 2026-10-27

### Changed

- Join WooCommerce `products` to the orders by merge: the peak on 4 million orders falls from 380 MB to 70 MB ([#44](https://github.com/Dactopus/dactopus-data-models/pull/44))

### Added

- Add the relationship `order_lines_to_products`, for sales by the product's current status ([#44](https://github.com/Dactopus/dactopus-data-models/pull/44))

## [0.7.0] - 2026-10-26

_Both store packages read new input tables and need one `dbt build --full-refresh` ([Upgrading](UPGRADING.md#070))._

### Changed

- Reread in Shopify's `order_lines` the orders whose refunds were loaded since the last run ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))
- Say in `orders.average_order_value` how each platform counts an order filtered by a category ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))

### Added

- **Breaking:** Read the Shopify input `products` and the WooCommerce inputs `wp_posts`, `wp_terms`, `wp_term_taxonomy` and `wp_term_relationships` ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))
- **Breaking:** Add `order_lines.returned_quantity` and `returned_amount`, with the metrics `items_returned`, `line_returned_amount` and `line_net_revenue` ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))
- Add `line_categories` and `line_brands`, with units, revenue, returns and net revenue by category and by brand ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))
- Add `products`, `product_categories` and `product_brands`, the catalog with its status and the date of the last sale ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))
- Export Shopify's products and their deletions in the README's `export_shopify.py` ([#41](https://github.com/Dactopus/dactopus-data-models/pull/41))

## [0.6.1] - 2026-10-25

_Metric names change ([Upgrading](UPGRADING.md#061))._

### Changed

- **Breaking:** Declare each metric on the dataset it reads, name it `dataset.metric`, and rename those named like a field or a dataset ([#39](https://github.com/Dactopus/dactopus-data-models/pull/39))

## [0.6.0] - 2026-10-23

### Changed

- Send "latest data", "last update" and "data up to" in the iot model to `last_contact_time` ([#35](https://github.com/Dactopus/dactopus-data-models/pull/35))
- Keep each site's coordinates in `devices_archive`, and read the snapshots once in `devices` ([#35](https://github.com/Dactopus/dactopus-data-models/pull/35))

### Added

- Add `deployment.yml` to every package, with the model, the variables by role and the daily tables a deployment tool needs ([#37](https://github.com/Dactopus/dactopus-data-models/pull/37))
- Add `tests/check_deployment.py`, which holds `deployment.yml` to its package and finds a table built in two time zones ([#37](https://github.com/Dactopus/dactopus-data-models/pull/37))

## [0.5.3] - 2026-10-22

_GA4 metric names change ([Upgrading](UPGRADING.md#053))._

### Changed

- **Breaking:** Rename the GA4 revenue metrics after GA4's gross purchase revenue, so that the GA4 and commerce models serve together ([#34](https://github.com/Dactopus/dactopus-data-models/pull/34))
- Remove the store's terms from the synonyms of the GA4 metrics ([#34](https://github.com/Dactopus/dactopus-data-models/pull/34))

## [0.5.2] - 2026-10-22

_The packages ship no dbt profile ([Upgrading](UPGRADING.md#052))._

### Removed

- **Breaking:** Remove `profiles.yml` from every package ([#33](https://github.com/Dactopus/dactopus-data-models/pull/33))

## [0.5.1] - 2026-10-22

_Serve with `--time-zone` and load the snapshots with the new query ([Upgrading](UPGRADING.md#051))._

### Changed

- Measure a Sensor.Community site's silence from its latest contact in the snapshots, not its latest reading ([#27](https://github.com/Dactopus/dactopus-data-models/pull/27))
- Make `devices` a view over the snapshots and the new table `devices_archive` ([#27](https://github.com/Dactopus/dactopus-data-models/pull/27))
- Keep one row per sensor in the snapshot query of the Sensor.Community README ([#27](https://github.com/Dactopus/dactopus-data-models/pull/27))
- Serve the commerce and GA4 models in the zone their package was built in ([#32](https://github.com/Dactopus/dactopus-data-models/pull/32))

### Added

- Add `devices.last_contact_at` and the metrics `last_contact_time` and `minutes_since_last_contact` ([#27](https://github.com/Dactopus/dactopus-data-models/pull/27))

## [0.5.0] - 2026-10-21

### Added

- Add the iot model `entities/iot.yaml`, a reference domain over one public dataset ([#24](https://github.com/Dactopus/dactopus-data-models/pull/24))
- Add the Sensor.Community package `sources/sensor_community` ([#24](https://github.com/Dactopus/dactopus-data-models/pull/24))

## [0.4.1] - 2026-10-15

_The lower memory needs the sorting keys of the Shopify `input.sql` ([Upgrading](UPGRADING.md#041))._

### Fixed

- Bound the Shopify package's memory: a shop of 2 million orders builds in 1.1 GB per query, where 4 GB ran out ([#23](https://github.com/Dactopus/dactopus-data-models/pull/23))

## [0.4.0] - 2026-10-15

_The WooCommerce package needs ClickHouse 26.7 and a grant ([Upgrading](UPGRADING.md#040))._

### Changed

- **Breaking:** Require ClickHouse 26.7 or newer for the WooCommerce package ([#20](https://github.com/Dactopus/dactopus-data-models/pull/20))
- **Breaking:** Require `ALTER MODIFY COMMENT` on WooCommerce's `refunds` ([#20](https://github.com/Dactopus/dactopus-data-models/pull/20))

### Fixed

- Fix `dbt source freshness` on dbt v2 with the packages' own freshness macros ([#19](https://github.com/Dactopus/dactopus-data-models/pull/19))
- Install one store package per dbt project in the README's `packages.yml` ([#19](https://github.com/Dactopus/dactopus-data-models/pull/19))
- Start a WooCommerce `refunds` run at its latest sync, not at the store's latest refund ([#20](https://github.com/Dactopus/dactopus-data-models/pull/20))
- Run each shared WooCommerce subquery once ([#20](https://github.com/Dactopus/dactopus-data-models/pull/20))
- Renumber a WooCommerce customer's orders after an order is moved and removed in one sync window ([#21](https://github.com/Dactopus/dactopus-data-models/pull/21))
- Take the latest sync of a WooCommerce row delivered twice ([#21](https://github.com/Dactopus/dactopus-data-models/pull/21))

## [0.3.0] - 2026-10-14

_A Shopify deployment needs one `dbt build --full-refresh` ([Upgrading](UPGRADING.md#030))._

### Changed

- Read `net_revenue` from `sales_events`, which by event date gives a period's sales as the store's reports do ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Count only the orders in the store's sales reports in every metric but `all_orders` and `all_orders_total` ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Date an order by the date the store's reports go by ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Set `on_schema_change: fail` in both order packages ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))

### Added

- **Breaking:** Add `in_sales_reports` and `cancelled_time` to Shopify's `orders` ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Add the WooCommerce package `sources/woocommerce` ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Add `sales_events`, each order, refund and cancellation on the day it counts ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))
- Add `orders.in_sales_reports` and the metrics `all_orders` and `all_orders_total` ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))

### Fixed

- Correct the description of `average_order_value`: WooCommerce Analytics does not subtract refunds ([#15](https://github.com/Dactopus/dactopus-data-models/pull/15))

## [0.2.1] - 2026-10-13

_The executor is now dactopus-ossie-clickhouse ([Upgrading](UPGRADING.md#021))._

### Changed

- Install the executor as dactopus-ossie-clickhouse, formerly ossie-clickhouse ([#11](https://github.com/Dactopus/dactopus-data-models/pull/11))
- Move to ossie-clickhouse 0.3.1: 0.2.2 could return wrong values for a compound expression ([#10](https://github.com/Dactopus/dactopus-data-models/pull/10))
- Name Shopify's "sales reversals (formerly returns)" in the README and `refunded_amount` ([#12](https://github.com/Dactopus/dactopus-data-models/pull/12))

## [0.2.0] - 2026-10-06

### Added

- Add the Shopify package `sources/shopify`, over the GraphQL Admin API ([#5](https://github.com/Dactopus/dactopus-data-models/pull/5))
- Add the commerce model `entities/commerce.yaml` ([#5](https://github.com/Dactopus/dactopus-data-models/pull/5))
- Add a diagram of the packages, their sources, ClickHouse, BI tools and AI agents ([#2](https://github.com/Dactopus/dactopus-data-models/pull/2))
- Add `ROADMAP.md` ([#2](https://github.com/Dactopus/dactopus-data-models/pull/2))

### Fixed

- Stop the README listing orders, line items and customers before they existed ([#2](https://github.com/Dactopus/dactopus-data-models/pull/2))

## [0.1.0] - 2026-10-05

_Initial release._

### Added

- Add the GA4 package `sources/ga4`, over the BigQuery export ([`e186a97`](https://github.com/Dactopus/dactopus-data-models/commit/e186a97))
- Add the web_analytics model `entities/web_analytics.yaml` ([`0076e69`](https://github.com/Dactopus/dactopus-data-models/commit/0076e69))

[0.13.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.13.0
[0.12.2]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.12.2
[0.12.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.12.1
[0.12.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.12.0
[0.11.2]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.11.2
[0.11.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.11.1
[0.11.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.11.0
[0.10.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.10.0
[0.9.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.9.0
[0.8.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.8.0
[0.7.2]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.7.2
[0.7.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.7.1
[0.7.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.7.0
[0.6.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.6.1
[0.6.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.6.0
[0.5.3]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.5.3
[0.5.2]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.5.2
[0.5.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.5.1
[0.5.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.5.0
[0.4.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.4.1
[0.4.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.4.0
[0.3.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.3.0
[0.2.1]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.2.1
[0.2.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.2.0
[0.1.0]: https://github.com/Dactopus/dactopus-data-models/releases/tag/v0.1.0
