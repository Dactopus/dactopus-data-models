# dactopus-data-models

[![CI](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Dactopus/dactopus-data-models)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Dactopus/dactopus-data-models)](https://github.com/Dactopus/dactopus-data-models/releases)

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format, with IoT devices as a reference domain. Two kinds of content:

- **Canonical entities**: sessions, events and purchases from web
  analytics; orders, their lines, discount codes, refunds, sales events
  and customers, and the catalog's products with their categories and
  brands, from the store; devices and their readings, the reference domain `iot`. They
  have the same shape whatever the data came from.
- **Source packages**: each maps one source onto those entities. GA4,
  Shopify, WooCommerce and Sensor.Community are available.

A store on Shopify and a WooCommerce store on its own MySQL look the
same once mapped, and one query works on both; unions add up several
stores, properties or networks
([deployment](docs/deployment.md#several-stores-properties-or-networks)).
BI tools read the tables, AI agents the model through
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse).
Plans: [ROADMAP.md](ROADMAP.md).

<a href="https://dactopus.github.io/dactopus-data-models/"><img src="docs/architecture.svg" width="680" alt="How the packages work: the GA4 export, Shopify's orders, a WooCommerce store's order tables and Sensor.Community's readings are loaded into input tables in your ClickHouse; the dbt packages build the canonical tables, and unions add up those of several stores; BI tools read them directly and AI agents through dactopus-ossie-clickhouse and the Ossie models."></a>

The [interactive version](https://dactopus.github.io/dactopus-data-models/)
explains each part and follows one purchase from GA4 to an agent's
answer.

## Sources

| Source | Entities | Guide |
| --- | --- | --- |
| GA4 (BigQuery export) | `events`, `sessions`, `purchases` | [sources/ga4](sources/ga4/README.md) |
| Shopify (GraphQL Admin API) | `orders`, `order_lines`, `refunds`, `sales_events`, `customers`, `products`, `line_categories`, `line_brands`, `order_discount_codes`, `product_categories`, `product_brands` | [sources/shopify](sources/shopify/README.md) |
| WooCommerce (the store's MySQL tables through CDC) | the same as Shopify | [sources/woocommerce](sources/woocommerce/README.md) |
| Sensor.Community (the archive's files and the API's snapshots) | `devices`, `readings`; the reference domain | [sources/sensor_community](sources/sensor_community/README.md) |

Where the two order sources differ, such as which orders the store's
reports count, the entities' descriptions say how. `iot` is a reference
domain drawn from one public dataset, the
[Sensor.Community](https://sensor.community/) air quality network; a
field goes in when any network of devices would have it
([Authoring rules](CONTRIBUTING.md#authoring-rules)).

## Quick start

Build the Shopify package over the rows the repository tests it with and
ask the commerce model about them. You need
[ClickHouse](https://clickhouse.com/docs/install) (26.8, the LTS release, or later), dbt v2
(`pip install dbt-oss`) or dbt v1 (`dbt-core` 1.11 with `dbt-clickhouse`),
and [dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse)
0.15.0 or later with its MCP server
(`pip install "dactopus-ossie-clickhouse[mcp]"`).

Add this profile to `~/.dbt/profiles.yml` (packages ship none). Over
TLS, as ClickHouse Cloud requires, add `secure: true`, set the HTTPS
port, and give dactopus-ossie-clickhouse `https://` URLs.

```yaml
dactopus:
  target: default
  outputs:
    default:
      type: clickhouse
      # The database the canonical tables are written to.
      schema: "{{ env_var('CLICKHOUSE_DATABASE', 'dactopus') }}"
      host: "{{ env_var('CLICKHOUSE_HOST', 'localhost') }}"
      port: "{{ env_var('CLICKHOUSE_PORT', '8123') | int }}"
      user: "{{ env_var('CLICKHOUSE_USER', 'default') }}"
      password: "{{ env_var('CLICKHOUSE_PASSWORD', '') }}"
      custom_settings:
        # The dbt v2 ClickHouse adapter (beta) decompresses LZ4 only, while
        # ClickHouse 26.x compresses HTTP responses with ZSTD by default.
        network_compression_method: LZ4
```

The rows, [`tests/shopify/fixture.sql`](tests/shopify/fixture.sql), are
twelve orders of a shop in New York and its thirteen products, each a
case the package must get right (refunds, cancellations, discounts, tax
included in prices, a gift card, a tip, import duties, repeated
deliveries, a product's type and vendor changed, a deleted product).

1. **Load** the input tables
   [`sources/shopify/input.sql`](sources/shopify/input.sql) and the rows
   into a database the variable `shopify_input_database` names.

   ```bash
   clickhouse client --param_db=shopify_sample_raw --multiquery < sources/shopify/input.sql
   clickhouse client --param_db=shopify_sample_raw --multiquery < tests/shopify/fixture.sql
   ```

2. **Build** in the shop's time zone, as Shopify's reports date orders
   (the default is UTC).

   ```bash
   CLICKHOUSE_DATABASE=shopify_sample dbt build --project-dir sources/shopify \
       --vars '{shopify_input_database: shopify_sample_raw, shopify_timezone: America/New_York}'
   ```

3. **Validate and check.** `check_numbers.py` asks 49 questions and
   compares the answers with numbers worked out by hand from the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/commerce.yaml --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/shopify_sample OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York uv run tests/shopify/check_numbers.py
   ```

4. **Ask.** Serve the model over MCP in the shop's zone
   ([connecting an agent](https://github.com/Dactopus/dactopus-ossie-clickhouse#readme)).
   Try net revenue, refunds by month, average order value and repeat
   orders by country, revenue by product type, products not sold since a
   date.

   ```bash
   dactopus-ossie-clickhouse serve entities/commerce.yaml \
       --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   ```

The same walk for each source, and for a store, your own:
[GA4](sources/ga4/README.md) (Google's public sample export),
[Shopify](sources/shopify/README.md) (then your store through the
GraphQL Admin API), [WooCommerce](sources/woocommerce/README.md)
(eighteen hand-written orders, then your store mirrored by PeerDB),
[Sensor.Community](sources/sensor_community/README.md) (one country's
sensors).

## Documentation

- What each model answers and its limits: [web analytics](docs/web_analytics.md),
  [commerce](docs/commerce.md), [iot](docs/iot.md).
- Where a package's numbers differ from the source's reports: the
  package README ([Shopify](sources/shopify/README.md#known-differences-from-shopifys-reports),
  [WooCommerce](sources/woocommerce/README.md#known-differences-from-woocommerce-analytics),
  [GA4](sources/ga4/README.md#known-differences-from-the-ga4-interface)).
- [Use in your dbt project](docs/deployment.md#use-in-your-dbt-project):
  `packages.yml`, input databases, labels, time zones, serving, unions.
- Checking an AI agent over your own data: [evals/README.md](evals/README.md).
- Layout, authoring rules, checks, and asking the questions of the
  canonical CSV tables with no dbt: [CONTRIBUTING.md](CONTRIBUTING.md).
- Changes by release: [CHANGELOG.md](CHANGELOG.md).

## Versioning

One version for the whole repository, [SemVer](https://semver.org), tags
`vX.Y.Z`; the Ossie schema version (`0.3.0.dev0`) is separate, and the
changelog names it for every release.

A breaking change stops a deployment working or changes its numbers:
renaming or removing a field, metric or column, changing a column's
type or what a metric means, a new required input column. Before 1.0
these come in a minor release, after it in a major one. New fields and
metrics are minor, fixes are patches.

A deployment pins one tag for its packages (`sources/<source>`), unions
(`unions/<domain>`) and Ossie models. Upgrading is changing the tag and
running `dbt build --full-refresh`, which rebuilds every table from the
input; the changelog marks the releases that need it and any change to
an input table.

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
