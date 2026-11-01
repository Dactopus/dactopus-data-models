# dactopus-data-models

[![CI](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Dactopus/dactopus-data-models/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Dactopus/dactopus-data-models)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Dactopus/dactopus-data-models)](https://github.com/Dactopus/dactopus-data-models/releases)

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format, with IoT devices as a reference domain. Two kinds of content:

- **Canonical entities**: sessions, events and purchases from web
  analytics; orders, their lines, refunds, sales events and customers,
  and the catalog's products with their categories and brands, from the
  store; devices and their readings, the reference domain `iot`. They
  have the same shape whatever the data came from.
- **Source packages**: each maps one source onto those entities. GA4,
  Shopify, WooCommerce and Sensor.Community are available.

Unions add up the tables of several stores, GA4 properties or networks
of one domain ([Several stores, properties or
networks](docs/deployment.md#several-stores-properties-or-networks)).

What comes next is in [ROADMAP.md](ROADMAP.md).

The aim: a store on Shopify and a store on its own Postgres look the same
once both are mapped, and one query works on both. The same model serves
BI tools through ClickHouse tables and AI agents through
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse).

<a href="https://dactopus.github.io/dactopus-data-models/"><img src="docs/architecture.svg" width="680" alt="How the packages work: the GA4 export, Shopify's orders, a WooCommerce store's order tables and Sensor.Community's readings are loaded into input tables in your ClickHouse; the dbt packages build the canonical tables, and unions add up those of several stores; BI tools read them directly and AI agents through dactopus-ossie-clickhouse and the Ossie models."></a>

Click the diagram for the [interactive version](https://dactopus.github.io/dactopus-data-models/):
what each part does and where it takes its settings from, and one
purchase followed from GA4 to an AI agent's answer.

## Sources

| Source | Entities | Guide |
| --- | --- | --- |
| GA4 (BigQuery export) | `events`, `sessions`, `purchases` | [sources/ga4](sources/ga4/README.md) |
| Shopify (GraphQL Admin API) | `orders`, `order_lines`, `refunds`, `sales_events`, `customers`, `products`, `line_categories`, `line_brands`, `product_categories`, `product_brands` | [sources/shopify](sources/shopify/README.md) |
| WooCommerce (the store's MySQL tables through CDC) | the same as Shopify | [sources/woocommerce](sources/woocommerce/README.md) |
| Sensor.Community (the archive's files and the API's snapshots) | `devices`, `readings`; the reference domain | [sources/sensor_community](sources/sensor_community/README.md) |

Both order sources map onto the same entities. Where they differ, such as
which orders the store's reports count, the entities' descriptions say
how.

`iot` is a reference domain: its entities are drawn from one public
dataset, the readings of the [Sensor.Community](https://sensor.community/)
air quality network, and from no business's own data. A field goes into
them when any network of devices would have it with the same meaning
([Authoring rules](CONTRIBUTING.md#authoring-rules)). No second source is
planned for it.

## Quick start

Build the Shopify package over the rows the repository tests it with and
ask the commerce model about them. You need
[ClickHouse](https://clickhouse.com/docs/install) (tested on 26.9), dbt v2
(`pip install dbt-oss`) or dbt v1 (`dbt-core` 1.11 with `dbt-clickhouse`),
and [dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse)
0.12.0 or later with its MCP server
(`pip install "dactopus-ossie-clickhouse[mcp]"`).

dbt connects through a profile named `dactopus`. A package ships none:
add this one to `~/.dbt/profiles.yml`, where dbt v2 and v1 look by
default. It reads the connection from `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT`
(HTTP, default 8123), `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`, and the
database the tables go to from `CLICKHOUSE_DATABASE` (default `dactopus`).
Over TLS, as ClickHouse Cloud requires, add `secure: true` and set the
HTTPS port, and give dactopus-ossie-clickhouse an `https://` URL in place
of the `http://` ones below: it uses TLS whenever the URL is `https://`,
on any port.

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

1. **Load** the package's input tables
   [`sources/shopify/input.sql`](sources/shopify/input.sql) and the rows.
   Their database is a parameter; the package reads it from the dbt
   variable `shopify_input_database`.

   ```bash
   clickhouse client --param_db=shopify_sample_raw --multiquery < sources/shopify/input.sql
   clickhouse client --param_db=shopify_sample_raw --multiquery < tests/shopify/fixture.sql
   ```

2. **Build** into a database of its own, in the shop's time zone. Order
   and refund dates are in it, as in Shopify's reports; the package's
   default is UTC.

   ```bash
   CLICKHOUSE_DATABASE=shopify_sample dbt build --project-dir sources/shopify \
       --vars '{shopify_input_database: shopify_sample_raw, shopify_timezone: America/New_York}'
   ```

3. **Validate** the model against the built tables and **check** its
   answers: `check_numbers.py` asks 41 questions through
   dactopus-ossie-clickhouse, in the zone of step 2, and compares the
   answers with numbers worked out by hand from the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/commerce.yaml --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/shopify_sample OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York python3 tests/shopify/check_numbers.py
   ```

4. **Ask.** Serve the model to an AI agent over MCP, in the zone of
   step 2, so that "today" in a question is the shop's date; the
   executor's [README](https://github.com/Dactopus/dactopus-ossie-clickhouse#readme)
   shows how to connect an agent. Try net revenue, refunds by month,
   average order value and repeat orders, by shipping country and new or
   returning customer; revenue and returns by product type and by
   vendor; products not sold since a date.

   ```bash
   dactopus-ossie-clickhouse serve entities/commerce.yaml \
       --url http://user:password@host:8123/shopify_sample --time-zone America/New_York
   ```

The same walk, and then your own store or property, for each source:

- [GA4](sources/ga4/README.md): Google's public sample export of 4.3
  million events, loaded from BigQuery, then your property's export.
- [Shopify](sources/shopify/README.md): the rows above, then your store
  through the GraphQL Admin API.
- [WooCommerce](sources/woocommerce/README.md): sixteen hand-written
  orders as change data capture writes them, then your store's tables
  mirrored by PeerDB.
- [Sensor.Community](sources/sensor_community/README.md): one country's
  sensors from the API's snapshots and the archive's files.

## Documentation

- What each model answers, how it defines sales, categories and
  customers, and its limits: [web analytics](docs/web_analytics.md),
  [commerce](docs/commerce.md), [iot](docs/iot.md).
- Where a package's numbers differ from the source's own reports, and
  why: [Shopify's reports](sources/shopify/README.md#known-differences-from-shopifys-reports),
  [WooCommerce Analytics](sources/woocommerce/README.md#known-differences-from-woocommerce-analytics),
  [the GA4 interface](sources/ga4/README.md#known-differences-from-the-ga4-interface).
- The packages in your dbt project, the label and time zone of each
  store, serving the models to agents, and unions over several stores,
  properties or networks: [docs/deployment.md](docs/deployment.md).
- Layout, what a source package is, out of scope, authoring rules and
  the checks before a pull request: [CONTRIBUTING.md](CONTRIBUTING.md).
- Changes by release: [CHANGELOG.md](CHANGELOG.md).

## Use in your dbt project

Add the packages you need to your project's `packages.yml`, pinned to a
release tag, and point dactopus-ossie-clickhouse at your target's database
with the Ossie models from the same tag:

```yaml
packages:
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.8.0
    subdirectory: sources/ga4
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.8.0
    subdirectory: sources/shopify
```

Each package reads its input from a database you name, labels every row
with its store, property or network (`source_id`), and dates orders in
the store's time zone when told it. The variables, the settings dbt v2
needs on ClickHouse, and serving several models to one agent:
[docs/deployment.md](docs/deployment.md).

## Versioning

One version for the whole repository, [SemVer](https://semver.org), tags
`vX.Y.Z`. The Ossie schema version (`0.2.0.dev0`) is separate: the model
files carry it, and the changelog names it for every release.

A breaking change is anything that stops a deployment working or changes
its numbers: renaming or removing a field, metric or column; changing a
column's type; changing what a metric means (the same columns, different
numbers); a new required column in a package's input. Before 1.0 such
changes come in a minor release, after 1.0 in a major one. New fields and
metrics are minor, fixes are patches.

A deployment pins a tag: the dbt package from the git tag with its
subdirectory (`sources/ga4`, `sources/shopify`, `sources/woocommerce`,
`sources/sensor_community`),
the Ossie model from the same tag. Upgrading is changing the tag and
running `dbt build --full-refresh`: a package never writes its input
tables, so every canonical table rebuilds from them. The changelog marks
releases that need the rebuild.

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
