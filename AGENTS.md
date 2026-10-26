# AGENTS.md

Guidance for AI coding agents working in this repository. What the project
is and why: [README.md](README.md).

## Language

All text in this repository is in English only: YAML descriptions,
`ai_context`, SQL comments, documentation, commit messages, issues. This
includes examples and test data written by hand.

## Scope

Everything must be releasable under Apache 2.0. Do not add:

- Anything that needs two sources at once: attribution, matching customers
  across systems, cross-source marts. A package covers one source.
- Data loading code or API connectors. Loading is a recipe in the README.
- Query execution. That is dactopus-ossie-clickhouse.
- Placeholders or stubs for any of the above.

The README describes what works today. Plans go in
[ROADMAP.md](ROADMAP.md), never into the README as if they existed.

## Layout

    entities/<domain>.yaml    one Ossie model per domain: its entities,
                              relationships and metrics
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      deployment.yml          what a deployment sets and reads: the Ossie
                              model, the variables for the input database
                              and the time zone, the tables counted per
                              day; every package ships one
      macros/                 SQL the package's models share
      models/<entity>.sql     one model per entity, named after it; an
                              entity that is a view over a built table
                              has that table as <entity>_<part>.sql
                              (devices_archive.sql)
      models/schema.yml       structural checks (dbt tests only)
      tests/                  singular dbt tests, for checks a generic
                              test cannot express
    tests/<source>/           hand-written input rows and the numbers the
                              model must answer over them
    tests/ask_model.py        asks the questions, shared by every source
    tests/check_freshness.py  checks the ages `dbt source freshness`
                              reports, shared by every source
    tests/check_deployment.py checks each package's deployment.yml against
                              the package and its built tables
    tests/profiles.yml        the dbt profile CI and the checks build
                              with; a package ships none
    docs/architecture.svg     the diagram, shown in the README and, with
    docs/index.html           the text for each part, on GitHub Pages;
                              update both in the change that alters
                              what they show

An entity holds schema (grain, keys), field descriptions and simple
metrics. A package holds the mapping from the source, the refresh
strategy and structural checks. Never put source-specific logic in an
entity. A model writes the table or view `<entity>`, which the entity's
`source` names. Descriptions live in the Ossie entity only; do not repeat them in
`schema.yml`.

No database name is written into a model, an entity or a package: the
deployment chooses them. A `source` is a bare table name, read in the
database dactopus-ossie-clickhouse connects to; a package writes to its dbt
target's database and reads its input from a variable
(`ga4_input_database`); `input.sql` takes the database as a query
parameter. `dactopus` and `ga4_raw` are only defaults for the sample
profile and the sample data. CI builds into other databases to keep it so.

## Model format

- Ossie schema version is pinned to `0.2.0.dev0`. Do not change it.
- Write expressions in `ANSI_SQL`.
- A metric that reads one dataset goes in that dataset's `metrics`,
  its fields named without the dataset; a count of its rows is
  `COUNT(*)`. The model's `metrics` holds only metrics over several
  datasets. A dataset's metric is not named like one of its fields or
  like a dataset: a count is `<row>_count` (`order_count`), a sum of a
  field `<field>_total` is `<field>_amount` (`discount_amount`).
  Descriptions name a dataset's metric as `dataset.metric`.
- Entities are plain Ossie. Mapping, refresh and checks belong in the
  package's dbt project, never in `custom_extensions`. The only extension
  used is dactopus-ossie-clickhouse's `CLICKHOUSE` namespace, for its `dedup` key.
- Models must work within dactopus-ossie-clickhouse limits: many-to-one
  joins on a declared primary or unique key, one path from a question's
  root to each dataset; a metric reads one fact table (two facts meet
  only on shared dimensions); no metric referencing another metric by
  name (repeat the expression); one field per time grain; `source` is a
  bare table name, never a query.
  Details: its [model authoring guide](https://github.com/Dactopus/dactopus-ossie-clickhouse/blob/main/docs/model-authoring.md).

## Authoring rules

- A field goes into a canonical entity only when at least two sources
  provide it. A source that has less of it still provides it when the
  meaning is the same: a category with its subcategories, where
  Shopify's product types have no subcategories. While a domain has a
  single source (GA4 for events), a field qualifies when its meaning
  does not depend on that source; where
  the second source is known but not yet packaged, it must exist there
  too, checked against its documentation. A source-only field is not
  modelled yet. A reference domain (`iot`) is built from one public
  dataset with no second source planned: a field qualifies when any
  network of devices would have it with the same meaning. Do not add
  canonical fields "for completeness".
- Every field and metric gets a description, and `ai_context` with
  synonyms where an analyst could phrase it differently. Agents answer
  from these; a missing description is a defect, not a style issue.
- Choices that look obvious are not: which date an order date is
  (placed, paid, shipped), which time zone, what identifies a customer.
  State the choice and the reason in the description. If the source
  data does not settle it, ask; do not pick silently.
- Source behaviour (what a status means, when a refund counts, duplicate
  events) comes from the source's documentation or the data. Cite the
  documentation in the package; do not rely on memory.
- A package adapted from a Fivetran dbt package says so and keeps
  Fivetran's license notice.

## ClickHouse traits

- A `SELECT` alias shadows a column of the same name in `WHERE`
  (`toDate(...) AS event_date` makes `WHERE event_date` see the Date, not
  the raw String). Filter raw columns in an inner subquery.
- Columns in `ORDER BY` of a `MergeTree` cannot be Nullable. Keys built
  from Nullable export fields need an explicit non-null guarantee.
- A CTE runs again at every reference, nested ones too. The WooCommerce
  models mark theirs `MATERIALIZED` and end with
  `woocommerce_query_settings()`; a new CTE there does the same.
- A sort over a prefix of the table's sorting key streams: ClickHouse
  reads the parts in that order and merges them, and a `LIMIT 1 BY` on
  the prefix takes each key's first row as it passes. A sort on other
  columns holds the whole table in memory. `shopify_latest` picks the
  latest version this way; a new input table's sorting key starts with
  the key the models dedupe by.
- An `INSERT ... SELECT` buffers rows per insert thread, up to
  `min_insert_block_size_bytes` each, before it writes a part: 2 GB on 8
  cores with the defaults. The Shopify models end with
  `shopify_query_settings()`, which bounds it; a new model there does
  the same.

## Verifying work

A model that validates can still return wrong numbers. For a change to a
model:

1. `dactopus-ossie-clickhouse validate <model> --url <clickhouse>/<database>`
   passes against loaded data.
2. `dbt build` of the package passes: models and their tests.
3. An incremental run over unchanged input changes nothing, and matches a
   `--full-refresh` build row for row.
4. A number the change affects matches a hand-written ClickHouse query
   over the same data. Show both queries and both results.
5. `tests/<source>/check_numbers.py` passes over that source's fixture
   (CI runs it). A changed number gets a new expected value with its
   derivation; a new source behaviour gets fixture rows. Check that a
   new case fails against the old code.
6. A change to descriptions, `ai_context` or model instructions changes
   what agents answer. Ask the questions it affects through
   `dactopus-ossie-clickhouse serve` (MCP), in fresh sessions, with more than one
   AI model, and compare every number in the answers with the
   hand-written queries.

Facts about ClickHouse behaviour and the GA4 export schema come from
running queries (`clickhouse local` or a server), not from memory.

## Development

Packages run on dbt v2 (`pip install dbt-oss`) and on dbt v1
(`dbt-core` 1.11 with `dbt-clickhouse`), with identical results. CI
installs the latest `dbt-oss` and `dbt-clickhouse`; the changelog names
the versions each release was tested with.
Sample data and loading: README, Quick start. A package ships no dbt
profile: the runner writes its own, a project that installs the packages
has one, and CI and the checks use `tests/profiles.yml`. Its connection:
`CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP), `CLICKHOUSE_USER`,
`CLICKHOUSE_PASSWORD`; target database `CLICKHOUSE_DATABASE` (default
`dactopus`).

```bash
dbt build --project-dir sources/ga4 --profiles-dir tests                 # models + tests
dbt build --project-dir sources/ga4 --profiles-dir tests --full-refresh  # rebuild all
```

Issues and pull requests in this repository are opened by the
maintainer, not by an agent on its own.

`tests/profiles.yml` and the README's sample profile set
`network_compression_method: LZ4`: the dbt v2 ClickHouse adapter (beta)
cannot read the ZSTD responses ClickHouse 26.x sends by default. dbt v2's
own `dbt source freshness` fails on ClickHouse for any project (it
selects `now()`, which arrives as an integer); each package's
`macros/freshness.sql` replaces it with a query that casts both times to
`DateTime64`. A project that installs the packages reaches these macros
through the `dispatch` setting in the README. Remove both once a
`dbt-oss` release fixes dbt-labs/dbt#16714.
