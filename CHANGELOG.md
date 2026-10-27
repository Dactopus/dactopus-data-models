# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/) as the README's
[Versioning](README.md#versioning) section applies them. Every release
names the Ossie schema version its models carry.

## [Unreleased]

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
  [README](README.md#known-differences-from-shopifys-reports). The saving
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

[Unreleased]: https://github.com/Dactopus/dactopus-data-models/compare/v0.7.1...HEAD
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
