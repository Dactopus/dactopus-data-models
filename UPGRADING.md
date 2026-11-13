# Upgrading

A deployment pins one tag for its packages, unions and Ossie models
([Versioning](README.md#versioning)). To move to a later tag, do the
steps of every release in between, oldest first. One
`dbt build --full-refresh` at the end serves every release that asks for
one; after a package, build the unions that read it. A release not
listed here needs only the new tag. What each release changed:
[CHANGELOG.md](CHANGELOG.md).

## 0.13.1

- Add the billing address to the Shopify input's `orders`; the README's
  export query reads it, and a loader must deliver it:

  ```sql
  ALTER TABLE shopify_raw.orders
      ADD COLUMN billing_country_code Nullable(String) AFTER shipping_zip,
      ADD COLUMN billing_province_code Nullable(String) AFTER billing_country_code,
      ADD COLUMN billing_city Nullable(String) AFTER billing_province_code;
  ```

- Export every Shopify order again, from before the first: the orders
  already loaded have no billing address until then. WooCommerce's
  input already has it (`wp_wc_order_addresses`).
- Run `dbt build --full-refresh` of the Shopify and WooCommerce
  packages: their `orders` gain `billing_country`, `billing_region` and
  `billing_city`, and an incremental run stops on the new columns.

## 0.13.0

- Serve the models with dactopus-ossie-clickhouse 0.15.0 or newer:
  0.14.0 and earlier refuse Ossie schema `0.3.0.dev0`.
- Run the WooCommerce package on ClickHouse 26.8 or newer.
- Run `dbt build` of the Shopify or WooCommerce package once before
  serving the model: it creates the view `order_discount_codes`, and
  until then dactopus-ossie-clickhouse serves the model without that
  dataset. No `--full-refresh` is needed.

## 0.12.2

- Grant the dbt user of the GA4 and Sensor.Community packages
  `ALTER MODIFY COMMENT` on their incremental tables (`events`,
  `sessions`, `purchases`; `readings`).
- Run `dbt build --full-refresh` of the GA4 and Sensor.Community
  packages: their tables record their label from this release on, and a
  table built by an earlier one records none, so its first incremental
  run stops. The Shopify and WooCommerce packages need none.

## 0.12.0

- Grant the dbt user `ALTER MODIFY COMMENT` on `orders`, `order_lines`
  and `refunds` of the Shopify and WooCommerce packages.
- Run `dbt build --full-refresh` of both packages, then the commerce
  union: `order_lines`, `line_categories`, `line_brands` and `refunds`
  gain a column, and tables built by an earlier release record no
  settings. One full refresh covers both.
- Rename the commerce metrics in saved questions, dashboards and agent
  prompts; result columns are named `dataset.metric` too. The numbers
  do not change.

  | Old | New |
  | --- | --- |
  | `items_sold`, `items_net`, `line_revenue`, `items_returned`, `line_returned_amount`, `line_net_revenue` | the same name on `order_lines`: `order_lines.line_revenue` |
  | `category_items_sold`, `category_revenue`, `category_items_returned`, `category_returned_amount`, `category_net_revenue` | the same name on `line_categories`: `line_categories.category_revenue` |
  | `brand_items_sold`, `brand_revenue`, `brand_items_returned`, `brand_returned_amount`, `brand_net_revenue` | the same name on `line_brands`: `line_brands.brand_revenue` |
  | `refund_count`, `refunds_total` | the same name on `refunds`: `refunds.refunds_total` |

## 0.11.0

- Serve the models with dactopus-ossie-clickhouse 0.11.0 or newer: they
  write expressions in the `sql` form, which older versions, and Ossie
  tools that read only `dialects`, do not load.

## 0.10.0

- Grant a user that reads a union's model `SELECT` on the union's
  database alone: its views read the databases they add up with the
  rights of the user who built them.
- Check the numbers through a union if row policies on the tables it
  adds up hide rows from its readers: the views now go under the
  builder's policies. A union changes on its next build.

## 0.9.0

- Run `dbt build --full-refresh` of every package: every table gains
  the label `source_id` as its first column, columns come in a new
  order and some types change. A query that reads the tables directly
  sees amounts as `Decimal(38, 8)` and never NULL, customer keys and
  Shopify's quantities as `Int64`, flags as `Bool` and WooCommerce's
  times as `DateTime('UTC')`.
- Set the package's `<source>_source_id` before that build if the
  deployment will hold more than one store, property or network: the
  default is the package's name.

## 0.8.0

- Run `dbt build --full-refresh` of the Shopify or WooCommerce package:
  `orders` gains columns, and WooCommerce's `orders.customer_id` changes
  type.
- Rename `orders.customers` to `orders.buyer_count` in saved questions
  and dashboards.
- Expect customer numbers to move: Shopify numbers cancelled orders in a
  customer's sequence (over the fixture `orders.repeat_order_share` goes
  from 5/7 to 6/9), and WooCommerce counts guests, one per email.

## 0.7.2

- Add `processed_at` to the Shopify input's `refunds`, giving the
  refunds already loaded their `created_at`; a loader must deliver it:

  ```sql
  ALTER TABLE shopify_raw.refunds ADD COLUMN processed_at DateTime('UTC') DEFAULT created_at AFTER created_at;
  ALTER TABLE shopify_raw.refunds MATERIALIZE COLUMN processed_at SETTINGS mutations_sync = 1;
  ALTER TABLE shopify_raw.refunds MODIFY COLUMN processed_at REMOVE DEFAULT;
  ```

- Export the orders again from before the first import if the store
  imported refunds with a past date, so that they arrive with their
  `processedAt`.
- Run `dbt build --full-refresh --select refunds+` of the Shopify
  package: an incremental run keeps the old dates of the refunds it does
  not reread, with no error.

## 0.7.0

- Load the new input tables: Shopify's `products` (the README's
  `export_shopify.py`); WooCommerce's `wp_posts`, `wp_terms`,
  `wp_term_taxonomy` and `wp_term_relationships`, in two more PeerDB
  mirrors (the package README, Your store, step 3).
- Run `dbt build --full-refresh` of the Shopify or WooCommerce package:
  `order_lines` gains columns.

## 0.6.1

- Rename the metrics in saved questions and dashboards; result columns
  are named `dataset.metric` too. The numbers and the fields do not
  change.

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

## 0.5.3

- Rename the GA4 metrics in saved questions and dashboards. The
  expressions, the numbers and the fields do not change.

  | Old | New |
  | --- | --- |
  | `revenue` | `gross_purchase_revenue` |
  | `revenue_usd` | `gross_purchase_revenue_usd` |
  | `average_order_value` | `average_gross_purchase_revenue` |

## 0.5.2

- Give a package run by hand with `--profiles-dir sources/<package>` a
  profile named `dactopus` in `~/.dbt/profiles.yml` or in a directory
  given with `--profiles-dir`: the packages ship none. The README's
  Quick start has one, the same as the removed profile.

## 0.5.1

- Load the Sensor.Community snapshots with the query of the package
  README, which keeps one row per sensor. Snapshots loaded by the query
  of 0.5.0 can show a sensor's last contact up to five minutes early.
- Serve the commerce and GA4 models with `--time-zone` set to the zone
  the package was built in, so that "today" is the store's or the
  property's date.

## 0.4.1

- Give the Shopify input tables the sorting keys of `input.sql` to get
  the lower memory of this release; `refunds` is now keyed
  `(order_id, id)`. With other keys the package builds the same rows at
  the old memory.

## 0.4.0

- Run the WooCommerce package on ClickHouse 26.7 or newer.
- Grant the WooCommerce dbt user `ALTER MODIFY COMMENT` on `refunds`,
  part of `ALTER TABLE` and separate from `ALTER DELETE`.
- Install one store package per dbt project: Shopify and WooCommerce
  write the same tables. Stores on both platforms build into separate
  databases.
- Turn on the packages' freshness macros on dbt v2 with the `dispatch`
  setting of the README.
- Run `dbt build --full-refresh` of the WooCommerce package to correct
  at once the `customer_order_number` that
  [#17](https://github.com/Dactopus/dactopus-data-models/issues/17) left
  stale; otherwise the next change to one of the customer's orders
  corrects it.

## 0.3.0

- Run `dbt build --full-refresh` of the Shopify package: its `orders`
  has new columns, and an incremental run now stops on them.

## 0.2.1

- Install the executor as dactopus-ossie-clickhouse instead of
  ossie-clickhouse; the old command still works in 0.4.x.
