# dactopus-data-models

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format. Two kinds of content:

- **Canonical entities**: orders, line items, customers, sessions, events,
  purchases. They have the same shape whatever the data came from.
- **Source packages**: they map one source (GA4, Shopify, WooCommerce, ...)
  onto those entities.

A store on Shopify and a store on its own Postgres look the same once both
are mapped: one query works on both. The same model serves BI tools through
ClickHouse tables and AI agents through
[ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse).

## Sources

| Source | Entities | Status |
| --- | --- | --- |
| GA4 (BigQuery export) | `events`, `sessions`, `purchases` | available |
| Shopify | `orders`, line items, customers | next |
| WooCommerce | `orders`, line items, customers | planned |

The `orders` entity is provisional until a second orders source maps onto
it. One source alone cannot show which fields are canonical.

## Quick start

Try the GA4 package on Google's public sample
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset)
(BigQuery; a free-tier GCP account is enough).

1. **Load.** Export the sample to Parquet in GCS and read it into ClickHouse
   with the `gcs()` table function.
   <!-- TBD: exact export and load commands -->
2. **Build.** <!-- TBD: depends on the transformation runner -->
3. **Validate** the model against the loaded tables:

   ```bash
   ossie-clickhouse validate <model> --url http://user:password@host:8123
   ```

4. **Ask.** Serve the model to an AI agent over MCP with
   `ossie-clickhouse serve`. Try sessions, conversion, revenue from
   `purchase`, each by traffic source and date.

## Layout

    entities/            one entity per Ossie YAML file
    sources/<source>/    one package per source; references entities

<!-- TBD: layout inside a package once the extension schema is settled -->

This is one repository, not one per source. Packages map onto shared
entities, so they are released together with them under a single version.
Consumers take the subdirectories they need.

## What a source package is

A package is more than a table schema. Every entity–source pair has six
parts:

| Part | Lives in | Example |
| --- | --- | --- |
| 1. Schema: row grain, keys | entity | one row per order |
| 2. Mapping from the source | package | where `refunded_total` comes from, how statuses map, what happens to currency |
| 3. Refresh strategy | package | by `updated_at` or a re-read window; dedup in `ReplacingMergeTree` |
| 4. Structural checks | package | uniqueness, not-null, freshness, `refunded_total <= total` |
| 5. Field descriptions | entity | plus `ai_context` and synonyms |
| 6. Simple metrics | entity | net revenue = `total - refunded_total` |

Part 2 is where the value is. Shopify counts a refund still in processing
as a refund and WooCommerce does not. GA4 records a purchase twice when the
thank-you page is reloaded. A package that gets the schema right and the
mapping wrong returns wrong numbers that look plausible.

## Out of scope

- Loading data. This README gives recipes; the tools are someone else's.
- Running queries. That is ossie-clickhouse.
- Reconciling with the source's own reports through its API.
- Anything that needs two sources at once: attributing sessions to
  orders, matching customers across systems, cross-source marts.
- API connectors (for example to the GA4 API) and Universal Analytics.

Everything here is Apache 2.0. If a file cannot be released under it, it
does not belong here.

## Authoring rules

**Format.** Ossie schema `0.2.0.dev0`, the only version the upstream
schema accepts today. Write expressions in `ANSI_SQL`; ossie-clickhouse
also accepts `OSSIE_SQL_2026`. Anything outside the standard (mapping,
refresh, checks) goes in `custom_extensions` under the
<!-- TBD: namespace --> namespace. The `CLICKHOUSE` namespace belongs to
ossie-clickhouse; its only key is `dedup`.

**The canon is selected, not designed.** A field that at least two sources
provide goes into the canonical entity. A field only one source has stays
in that source's extension (a `source_attrs` map or a separate table) until
a second source needs it.

**Descriptions are part of the model.** Agents answer from descriptions,
synonyms and `ai_context`. Without them even strong models guess. A dbt
`.yml` description is the minimum, not the target.

**Name the "obvious" choices.** Models break on what looks obvious:
- Order date: placed, paid or shipped? Store time zone or UTC?
- Customer: account, email or card?

A package states which one it uses and why.

**ossie-clickhouse limits are rules here.**
- One root dataset per question.
- Joins are many-to-one only, on a declared primary or unique key, so a
  mart that combines facts is materialized as one fact table.
- A metric cannot reference another metric by name; repeat the
  expression.
- No time grain or derived dimensions: declare one field per grain.
- `source` is `database.table`, not a query.

See its [model authoring guide](https://github.com/Dactopus/ossie-clickhouse/blob/main/docs/model-authoring.md).

**Access control is not modelled.** It comes from ClickHouse grants.

## Versioning

<!-- TBD: how library versions relate to Ossie schema versions; how a
deployment stays on an old version until it migrates -->

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
