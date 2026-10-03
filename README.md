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
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset):
4.3 million events from November 2020 to January 2021. You need
[ClickHouse](https://clickhouse.com/docs/install), the
[gcloud CLI](https://cloud.google.com/sdk/docs/install),
[uv](https://docs.astral.sh/uv/) and dbt v2 (`pip install dbt-oss`).

1. **Export.** A Google Cloud project in the
   [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) is
   enough: no billing account, no Cloud Storage bucket.

   ```bash
   gcloud auth login
   gcloud projects create <project-id>
   gcloud services enable bigquery.googleapis.com --project <project-id>
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> data/ga4
   ```

   `export_ga4.py` reads the daily tables with the BigQuery Storage Read
   API and writes one Parquet file per day (about 200 MB, 10 minutes). It
   passes the gcloud login token explicitly, so a
   `GOOGLE_APPLICATION_CREDENTIALS` set for another project does not get
   in the way:

   ```python
   import pathlib, subprocess, sys
   import pyarrow.parquet as pq
   from google.cloud import bigquery
   from google.oauth2.credentials import Credentials

   project, out = sys.argv[1], pathlib.Path(sys.argv[2])
   out.mkdir(parents=True, exist_ok=True)
   token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
   client = bigquery.Client(project=project, credentials=Credentials(token))
   dataset = "bigquery-public-data.ga4_obfuscated_sample_ecommerce"
   for table in client.list_tables(dataset):
       path = out / f"{table.table_id}.parquet"
       if not path.exists():
           rows = client.list_rows(client.get_table(table)).to_arrow(create_bqstorage_client=True)
           pq.write_table(rows, path, compression="zstd")
   ```

2. **Load** into the package's input table
   [`sources/ga4/input.sql`](sources/ga4/input.sql). It declares only the
   columns the package reads; any other way of delivering the export must
   fill the same table.

   ```bash
   clickhouse client --multiquery < sources/ga4/input.sql
   clickhouse local --query "
     SELECT event_date, event_timestamp, event_name, event_params,
            user_pseudo_id, user_id,
            tuple(device.category) AS device, tuple(geo.country) AS geo,
            tuple(ecommerce.purchase_revenue, ecommerce.tax_value,
                  ecommerce.shipping_value, ecommerce.transaction_id) AS ecommerce
     FROM file('data/ga4/*.parquet') FORMAT Native" |
   clickhouse client --query "
     INSERT INTO ga4_raw.events (event_date, event_timestamp, event_name,
       event_params, user_pseudo_id, user_id, device, geo, ecommerce)
     FORMAT Native"
   ```

3. **Build** the canonical tables in the `dactopus` database. Connection
   settings come from `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP, default
   8123), `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`.

   ```bash
   dbt build --project-dir sources/ga4 --profiles-dir sources/ga4
   ```

4. **Validate** the model against the loaded tables:

   ```bash
   ossie-clickhouse validate <model> --url http://user:password@host:8123
   ```

5. **Ask.** Serve the model to an AI agent over MCP with
   `ossie-clickhouse serve`. Try sessions, conversion, revenue from
   `purchase`, each by traffic source and date.

## Layout

    entities/                 one entity per Ossie YAML file
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      models/                 one model per entity, named after it
      models/schema.yml       structural checks (dbt tests)

A package's model writes the entity's table in the `dactopus` database;
the entity's Ossie `source` points at it, and
`ossie-clickhouse validate --url` checks that the package delivers every
column the entity declares. A deployment picks one package per entity.

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
also accepts `OSSIE_SQL_2026`. Mapping, refresh and checks live in the
package's dbt project, not in the Ossie files, so entities stay plain Ossie
that any Ossie tool reads. The only extension used is ossie-clickhouse's
`CLICKHOUSE` namespace and its `dedup` key.

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
