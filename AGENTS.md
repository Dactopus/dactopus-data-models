# AGENTS.md

Guidance for AI coding agents working in this repository. What the project
is and why: [README.md](README.md). How the repository is laid out, what a
source package is, what is out of scope, the authoring rules and the
checks before a pull request: [CONTRIBUTING.md](CONTRIBUTING.md). This
file holds what an agent applies while writing and CONTRIBUTING.md does
not state.

## Language

All text in this repository is in English only: YAML descriptions,
`ai_context`, SQL comments, documentation, commit messages, issues. This
includes examples and test data written by hand.

## Scope

Everything must be releasable under Apache 2.0. What does not belong
here: [Out of scope](CONTRIBUTING.md#out-of-scope). Do not add
placeholders or stubs for any of it either: no loader skeletons, no
cross-source marts "to fill in later".

The README describes what works today. Plans go in
[ROADMAP.md](ROADMAP.md), never into the README as if they existed.

## Documentation

The files are listed in [Layout](CONTRIBUTING.md#layout). A change ships
with the page that states what it changes, in the same pull request:

- a package's variables, loading recipe, known differences from the
  source's own reports: the package's `README.md`;
- what a model answers, how it defines a term or where it stops:
  `docs/<domain>.md`;
- how the packages go into a dbt project, labels, time zones, serving,
  unions: `docs/deployment.md`;
- the checks, the layout, the authoring rules: `CONTRIBUTING.md`;
- what the diagram shows: `docs/architecture.svg` and `docs/index.html`,
  both.

A number in a guide (a count of metrics or questions, a memory
measurement) is checked against the code before it is written.
Descriptions of fields and metrics live in the Ossie entity only; do not
repeat them in `schema.yml`.

## Models, packages and unions

An entity holds schema (grain, keys), field descriptions and simple
metrics. A package holds the mapping from the source, the refresh
strategy and structural checks. Never put source-specific logic in an
entity. A model writes the table or view `<entity>`, which the entity's
`source` names.

No database name is written into a model, an entity or a package: the
deployment chooses them. A `source` is a bare table name, read in the
database dactopus-ossie-clickhouse connects to; a package writes to its dbt
target's database and reads its input from a variable
(`ga4_input_database`); `input.sql` takes the database as a query
parameter. `dactopus` and `ga4_raw` are only defaults for the sample
profile and the sample data. CI builds into other databases to keep it so.

Every model writes `source_id`, the label of the store, property or
network its rows come from, as its first column: `<package>_source_id()`,
or in a view over one built table, that table's column. Its default
is the package's name; CI builds with another label, so no model may
assume it. In the Ossie models `source_id` is each
dataset's first field, first in every `primary_key`, on both sides of
every relationship, and in every `COUNT(DISTINCT ...)` beside the
counted column: `COUNT(DISTINCT source_id, customer_id)`, never a tuple,
which counts a NULL as a value. A package's `order_by` and `unique_key`
leave it out: a database holds one label.

A union reads the tables of the databases its variable lists
(`commerce_union_databases`) and casts nothing. Its macro compares each
database's column types with the contract and fails the build on any
other: the contract alone would pass one that `UNION ALL` widens to the
contract's type (`Decimal(26, 8)` to `Decimal(38, 8)`). A dataset or a column the
Ossie model starts to read goes into the union's `schema.yml` in the same
change, with its type; `tests/check_contracts.py` requires it. A union
does not test keys: each package tests the key of each dataset without
`source_id` (`unique`, or `<package>_unique_key` for several columns),
and with one label in a database and each label in one database
(`<domain>_union_distinct_source_ids`), the key is unique in the union.
`macros/union.sql` is the same file in every union, and
`macros/freshness.sql` in every package; change all copies at once.

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
- Every model has a dbt contract (`+contract` in `dbt_project.yml`):
  `schema.yml` lists each column with its ClickHouse type, and the
  model's last `SELECT` casts to it. The columns the Ossie model reads
  come first, in the order it first reads them, with one type in every
  package of the domain; `tests/check_contracts.py` checks both. The
  common types of `commerce`: amounts `Decimal(38, 8)`, not Nullable (WooCommerce
  keeps `decimal(26,8)`, and line totals at up to 6 decimals); the
  customer key `Int64` (WooCommerce's guests are negative), cast from
  Shopify's unsigned ids with `accurateCast`, which fails where a plain
  cast wraps; quantities `Int64`; times `DateTime('UTC')` (both sources
  keep whole seconds); flags `Bool`. A NULL in a column that is not
  Nullable fails the build: do not turn it into 0 with `assumeNotNull`
  alone.
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

The rules are in [Authoring rules](CONTRIBUTING.md#authoring-rules):
which fields enter the canon, descriptions and `ai_context`, naming the
choices that look obvious. Where source behaviour comes from and how it
is cited: [Adding a source package](CONTRIBUTING.md#adding-a-source-package).
For an agent they mean:

- A missing description or `ai_context` is a defect, not a style issue:
  agents answer from them.
- If the source data does not settle a choice (which date an order date
  is, which time zone, what identifies a customer), ask; do not pick
  silently.

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
- A `LEFT JOIN` without a match fills a non-Nullable column with its
  type's default (0 for an amount) only while `join_use_nulls` is 0; a
  server or profile may set 1. The Shopify and WooCommerce settings
  macros set 0, so every model that ends with them builds the same under
  either; `tests/profiles.yml` sets 1 to prove it.
- An `INSERT ... SELECT` buffers rows per insert thread, up to
  `min_insert_block_size_bytes` each, before it writes a part: 2 GB on 8
  cores with the defaults. The Shopify models end with
  `shopify_query_settings()`, which bounds it; a new model there does
  the same.

## Verifying work

A model that validates can still return wrong numbers. A change to a
model or a package is done when every step of
[Checks before a pull request](CONTRIBUTING.md#checks-before-a-pull-request)
has passed, and the report shows the hand-written queries and both
results. A change to descriptions, `ai_context` or model instructions is
checked by asking, in fresh sessions with more than one AI model, the
questions it affects.

Facts about ClickHouse behaviour and a source's export schema come from
running queries (`clickhouse local` or a server) or from the source's
documentation, cited next to the code, not from memory.

## Development

Packages run on dbt v2 (`pip install dbt-oss`) and on dbt v1
(`dbt-core` 1.11 with `dbt-clickhouse`), with identical results. CI
installs the latest `dbt-oss` and `dbt-clickhouse`; the changelog names
the versions each release was tested with.
Sample data and loading: the package READMEs. A package ships no dbt
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
through the `dispatch` setting in `docs/deployment.md`. Remove both once a
`dbt-oss` release fixes dbt-labs/dbt#16714.
