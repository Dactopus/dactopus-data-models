# dactopus-data-models

Open data models for e-commerce on [ClickHouse](https://clickhouse.com/docs),
written in the [Apache Ossie](https://github.com/apache/ossie) semantic model
format. Two kinds of content:

- **Canonical entities**: sessions, events and purchases today; orders,
  line items and customers next. They have the same shape whatever the
  data came from.
- **Source packages**: each maps one source onto those entities. GA4 is
  available; Shopify and WooCommerce are planned.

The aim: a store on Shopify and a store on its own Postgres look the same
once both are mapped, and one query works on both. The same model serves
BI tools through ClickHouse tables and AI agents through
[ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse).

<a href="https://dactopus.github.io/dactopus-data-models/"><img src="docs/architecture.svg" width="680" alt="How the GA4 package works: the GA4 export is loaded into an input table in your ClickHouse; the dbt package builds the canonical tables; BI tools read them directly and AI agents through ossie-clickhouse and the Ossie model."></a>

Click the diagram for the [interactive version](https://dactopus.github.io/dactopus-data-models/):
what each part does and where it takes its settings from, and one
purchase followed from GA4 to an AI agent's answer.

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
[uv](https://docs.astral.sh/uv/), dbt v2 (`pip install dbt-oss`) and
[ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse) 0.2.2 or
later with its MCP server
(`pip install "ossie-clickhouse[mcp] @ git+https://github.com/Dactopus/ossie-clickhouse@v0.2.2"`).
Tested on ClickHouse 26.9.

1. **Export.** A Google Cloud project in the
   [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) is
   enough: no billing account, no Cloud Storage bucket. Save the script
   below as `export_ga4.py` and run:

   ```bash
   gcloud auth login
   gcloud projects create <project-id>
   gcloud services enable bigquery.googleapis.com --project <project-id>
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> data/ga4
   ```

   The script reads the daily tables with the BigQuery Storage Read API
   and writes one Parquet file per day (about 200 MB, 10 minutes). It
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
   fill the same table. Its database is a parameter, `ga4_raw` here; the
   package reads another one from the dbt variable `ga4_input_database`.

   ```bash
   clickhouse client --param_db=ga4_raw --multiquery < sources/ga4/input.sql
   clickhouse local --query "
     SELECT event_date, event_timestamp, event_name, event_params,
            user_pseudo_id, user_id,
            tuple(device.category) AS device, tuple(geo.country) AS geo,
            tuple(ecommerce.purchase_revenue, ecommerce.purchase_revenue_in_usd,
                  ecommerce.tax_value,
                  ecommerce.shipping_value, ecommerce.transaction_id) AS ecommerce
     FROM file('data/ga4/*.parquet') FORMAT Native" |
   clickhouse client --query "
     INSERT INTO ga4_raw.events (event_date, event_timestamp, event_name,
       event_params, user_pseudo_id, user_id, device, geo, ecommerce)
     FORMAT Native"
   ```

   The sample is older than the `session_traffic_source_last_click`
   column. Exports from October 2024 on have it with the
   `cross_channel_campaign` record the package reads: load it too, adding
   the column to the `INSERT` list and this expression to the `SELECT`.
   Without it the package falls back to the first source seen in a
   session, and revenue by source will not match the GA4 interface.

   ```sql
   tuple(tuple(session_traffic_source_last_click.cross_channel_campaign.source,
               session_traffic_source_last_click.cross_channel_campaign.medium,
               session_traffic_source_last_click.cross_channel_campaign.campaign_name))
     AS session_traffic_source_last_click
   ```

3. **Build** the canonical tables. Connection settings come from
   `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP, default 8123),
   `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`; the database the tables go
   to from `CLICKHOUSE_DATABASE` (default `dactopus`).

   ```bash
   dbt build --project-dir sources/ga4 --profiles-dir sources/ga4
   ```

4. **Validate** the model against the built tables. The model names its
   tables without a database: ossie-clickhouse reads them in the database
   of its URL.

   ```bash
   ossie-clickhouse validate entities/web_analytics.yaml --url http://user:password@host:8123/dactopus
   ```

5. **Ask.** Serve the model to an AI agent over MCP with
   `ossie-clickhouse serve entities/web_analytics.yaml --url ...`, the
   same URL; its [README](https://github.com/Dactopus/ossie-clickhouse#readme)
   shows how to connect an agent. Try sessions, conversion rate and
   revenue, by traffic source, device, country and date.

## What the GA4 model answers

[`entities/web_analytics.yaml`](entities/web_analytics.yaml) has 12
metrics:

- sessions: `sessions`, `engaged_sessions`, `engagement_rate`, `users`,
  `session_conversion_rate`, `user_conversion_rate`;
- purchases: `purchases`, `revenue`, `revenue_usd`, `average_order_value`;
- events: `events`, `page_views`.

They break down by date, week and month; traffic source, medium and
campaign; landing page, device and country; purchase currency; event
name and page. The descriptions in the file say what each one counts.

## Known differences from the GA4 interface

Numbers from the model and from the GA4 interface can differ for reasons
the model states in its descriptions:

- **Sessions and users** are counted exactly; the GA4 interface estimates
  them, so they differ slightly. A user is a browser on a device
  (`user_pseudo_id`), not a person.
- **Traffic source** matches the interface (last non-direct click) only
  for exports from October 2024 on, loaded with the
  `session_traffic_source_last_click` column. Older exports fall back to
  the first source seen in the session.
- **Purchases** are what the site sent to GA4, not the store's orders:
  purchases made with tracking blocked are missing. A purchase sent twice
  with the same transaction id counts once, as in GA4.
- **Revenue** is in the currency of each purchase. A store that sells in
  several currencies has to read it by `purchases.currency`;
  `revenue_usd` is converted by Google at a rate it does not document.
- **Dates** are in the GA4 property's time zone; a session that crosses
  midnight counts once, on the day it started. Properties outside UTC
  are not tested yet ([#1](https://github.com/Dactopus/dactopus-data-models/issues/1)).

## Use in your dbt project

Add the package to your project's `packages.yml`, pinned to a release tag:

```yaml
packages:
  - git: https://github.com/Dactopus/dactopus-data-models.git
    revision: v0.1.0
    subdirectory: sources/ga4
```

It writes `events`, `sessions` and `purchases` to your target's database
and reads its input from `ga4_raw.events` unless you name another
database:

```yaml
vars:
  dactopus_ga4:
    ga4_input_database: my_ga4_export
```

Point ossie-clickhouse at your target's database
(`--url http://host:8123/<database>`) and take the Ossie model from the
same tag. On dbt v2 with ClickHouse 26.x, set
`custom_settings: {network_compression_method: LZ4}` in your profile, as
[`sources/ga4/profiles.yml`](sources/ga4/profiles.yml) does: the v2
ClickHouse adapter (beta) cannot read ClickHouse's default ZSTD
responses.

Several GA4 properties: each exports to its own BigQuery dataset. Build
the package once per property, each with its own input and target
database, and serve the model once per target. A total across properties
is not modelled.

## Layout

    entities/<domain>.yaml    one Ossie model per domain (web_analytics, ...)
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      models/                 one model per entity, named after it
      models/schema.yml       structural checks (dbt tests)
      tests/                  checks that need their own SQL
    tests/<source>/           hand-written input rows and the numbers the
                              model must answer over them
    docs/                     the diagram above and its interactive page

A package's model writes the entity's table, named after it, in the
database the deployment chooses. The entity's dataset in the domain's
Ossie model names that table without a database (an Ossie model is one
file, since relationships and metrics span entities), so one model serves
any database ossie-clickhouse connects to, and
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
provide goes into the canonical entity. While a domain has a single source
(GA4 for events), a field qualifies when its meaning does not depend on
that source. A field only one source has is not modelled until a second
source needs it.

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
- `source` is a table name without a database, not a query: the
  deployment picks the database.

See its [model authoring guide](https://github.com/Dactopus/ossie-clickhouse/blob/main/docs/model-authoring.md).

**Access control is not modelled.** It comes from ClickHouse grants.

## Versioning

One version for the whole repository, [SemVer](https://semver.org), tags
`vX.Y.Z`. The Ossie schema version (`0.2.0.dev0`) is separate: the model
files carry it, and the changelog names it for every release.

A breaking change is anything that stops a deployment working or changes
its numbers: renaming or removing a field, metric or column; changing what
a metric means (the same columns, different numbers); a new required
column in a package's input. Before 1.0 such changes come in a minor
release, after 1.0 in a major one. New fields and metrics are minor, fixes
are patches.

A deployment pins a tag: the dbt package from the git tag with its
subdirectory (`sources/ga4`), the Ossie model from the same tag. Upgrading
is changing the tag and running `dbt build --full-refresh`: a package never
writes its input table, so every canonical table rebuilds from it. The
changelog marks releases that need the rebuild.

## License

Apache License 2.0. Packages adapted from Fivetran's dbt packages (Apache
2.0) say so in the package and keep the original notices.
