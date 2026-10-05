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
- Query execution. That is ossie-clickhouse.
- Placeholders or stubs for any of the above.

## Layout

    entities/<domain>.yaml    one Ossie model per domain: its entities,
                              relationships and metrics
    sources/<source>/         one package per source, a dbt project:
      input.sql               the input table the package accepts
      models/<entity>.sql     one model per entity, named after it
      models/schema.yml       structural checks (dbt tests only)
    tests/<source>/           hand-written input rows and the numbers the
                              model must answer over them
    docs/architecture.svg     the diagram, shown in the README and, with
    docs/index.html           the text for each part, on GitHub Pages;
                              update both in the change that alters
                              what they show

An entity holds schema (grain, keys), field descriptions and simple
metrics. A package holds the mapping from the source, the refresh
strategy and structural checks. Never put source-specific logic in an
entity. A model writes the table `<entity>`, which the entity's `source`
names. Descriptions live in the Ossie entity only; do not repeat them in
`schema.yml`.

No database name is written into a model, an entity or a package: the
deployment chooses them. A `source` is a bare table name, read in the
database ossie-clickhouse connects to; a package writes to its dbt
target's database and reads its input from a variable
(`ga4_input_database`); `input.sql` takes the database as a query
parameter. `dactopus` and `ga4_raw` are only defaults for the standalone
profile and the sample. CI builds into other databases to keep it so.

## Model format

- Ossie schema version is pinned to `0.2.0.dev0`. Do not change it.
- Write expressions in `ANSI_SQL`.
- Entities are plain Ossie. Mapping, refresh and checks belong in the
  package's dbt project, never in `custom_extensions`. The only extension
  used is ossie-clickhouse's `CLICKHOUSE` namespace, for its `dedup` key.
- Models must work within ossie-clickhouse limits: one root dataset per
  question; many-to-one joins on a declared primary or unique key; no
  metric referencing another metric by name (repeat the expression); one
  field per time grain; `source` is a bare table name, never a query.
  Details: its [model authoring guide](https://github.com/Dactopus/ossie-clickhouse/blob/main/docs/model-authoring.md).

## Authoring rules

- A field goes into a canonical entity only when at least two sources
  provide it. While a domain has a single source (GA4 for events), a
  field qualifies when its meaning does not depend on that source; a
  source-only field is not modelled yet. Do not add canonical fields "for
  completeness".
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

## Verifying work

A model that validates can still return wrong numbers. For a change to a
model:

1. `ossie-clickhouse validate <model> --url <clickhouse>/<database>`
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

Facts about ClickHouse behaviour and the GA4 export schema come from
running queries (`clickhouse local` or a server), not from memory.

## Development

Packages run on dbt v2 (`pip install dbt-oss`, tested 2.0.5) and on dbt
v1 (`dbt-core` 1.11 with `dbt-clickhouse` 1.10), with identical results.
Sample data and loading: README, Quick start. Connection: `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP),
`CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`; target database
`CLICKHOUSE_DATABASE` (default `dactopus`).

```bash
dbt build --project-dir sources/ga4 --profiles-dir sources/ga4                 # models + tests
dbt build --project-dir sources/ga4 --profiles-dir sources/ga4 --full-refresh  # rebuild all
```

The package profile sets `network_compression_method: LZ4`: the dbt v2
ClickHouse adapter (beta) cannot read the ZSTD responses ClickHouse 26.x
sends by default. `dbt source freshness` fails on that adapter for any
project (it selects `now()`, which arrives as an integer); run freshness
on dbt v1.
