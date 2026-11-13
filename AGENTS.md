# AGENTS.md

The project: [README.md](README.md). Layout, scope, authoring rules and
checks: [CONTRIBUTING.md](CONTRIBUTING.md). A rule both files state
changes in both.

## Rules

- English only: YAML, `ai_context`, SQL comments, docs, commits, issues,
  test data.
- Everything is releasable under Apache 2.0; nothing from
  [Out of scope](CONTRIBUTING.md#out-of-scope), no stubs for it.
- Issues and pull requests are opened by the maintainer, not by an
  agent on its own.
- If the source data does not settle a choice (which date an order date
  is, which time zone, what identifies a customer), ask.
- Facts about ClickHouse or a source's schema come from running queries
  or from the source's documentation, cited next to the code.

## Checks

```bash
uv run tests/check_contracts.py                                  # no server
dbt build --project-dir sources/<source> --profiles-dir tests    # --full-refresh rebuilds all
dactopus-ossie-clickhouse validate entities/<domain>.yaml --url http://host:8123/<db> [--time-zone <zone>]
OSSIE_CLICKHOUSE_URL=http://host:8123/<db> OSSIE_CLICKHOUSE_TIME_ZONE=<zone> uv run tests/<source>/check_numbers.py
uv run tests/export_canon.py <source> && uv run tests/run_canon.py <source> --engine clickhouse
uv run tests/check_evals.py
```

The connection: `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP),
`CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`. When
each check applies: [Checks before a pull
request](CONTRIBUTING.md#checks-before-a-pull-request).

- A model change is done when every check passed and the report shows
  the hand-written queries and both results.
- A change to descriptions, `ai_context` or instructions is checked by
  asking the questions it affects through `dactopus-ossie-clickhouse
  serve`, in fresh sessions with more than one AI model.

## Documentation

- Docs state the current state; history goes in `CHANGELOG.md` and
  `UPGRADING.md` only.
- A change updates its page in the same pull request (which page:
  [Layout](CONTRIBUTING.md#layout)). A breaking change, or one a
  deployment must act on (`--full-refresh`, an input column, a grant),
  adds its steps under `## Unreleased` in `UPGRADING.md`.
- `CHANGELOG.md` follows [Common Changelog](https://common-changelog.org)
  and is written at release
  ([Releasing](CONTRIBUTING.md#releasing)); a pull request leaves it
  alone.
- A number in a guide is counted from the code before it is written.
- Field and metric descriptions live in the Ossie entity only.
- The README describes what works today; plans go in `ROADMAP.md`.

## Models and packages

- An entity holds grain, keys, descriptions and simple metrics, never
  source-specific logic; the package holds mapping, refresh and checks.
- No database name in a model, entity or package: `source` is a bare
  table name, input comes from a variable. CI builds into other
  databases.
- Every model writes `source_id` first, tested by
  `<package>_one_source_id`; CI builds under another label, so no model
  assumes the default. `order_by` and `unique_key` leave it out.
- Count across stores as
  `COUNT(DISTINCT source_id || '/' || CAST(customer_id AS VARCHAR))`: a
  tuple counts a NULL, and DuckDB rejects `COUNT(DISTINCT a, b)`.
- A variable the built rows depend on goes in `meta.guarded_vars` with
  its default (the `time_zone` and `source_id` roles always), any other
  in `meta.free_vars`. A release that starts to guard one keeps its
  default.
- `macros/union.sql` (unions) and `macros/freshness.sql`,
  `macros/settings.sql` (packages) are identical copies: change all.
- A column the Ossie model starts to read goes into the union's
  `schema.yml` in the same change.

## Model format

- Ossie schema `0.3.0.dev0`, pinned. Expressions in `sql`; `dialects`
  only for a vendor variant. No extension but `CLICKHOUSE.dedup`.
- A metric reads one dataset and sits in its `metrics`; the model has
  none of its own. A dataset that needs another's column carries it.
- Metric names: `<row>_count`, `<field>_amount` for a sum of
  `<field>_total`, never a field's or dataset's name;
  `orders.all_orders` is the exception. Descriptions write
  `dataset.metric`.
- Every model has a dbt contract; the last `SELECT` casts to it. The
  columns the Ossie model reads come first, in the order it reads them.
- Commerce types: amounts `Decimal(38, 8)` not Nullable; customer key
  `Int64` (Shopify's unsigned ids through `accurateCast`); quantities
  `Int64`; times `DateTime('UTC')`; flags `Bool`, read alone, never
  `= 1`. Do not hide a NULL with `assumeNotNull` alone.
- dactopus-ossie-clickhouse limits
  ([guide](https://github.com/Dactopus/dactopus-ossie-clickhouse/blob/main/docs/model-authoring.md)):
  many-to-one joins on a declared key, one path to each dataset; two
  facts meet only on shared dimensions; no metric references another;
  one field per time grain.
- A rule about one dataset, field or metric goes in its description.
  The model's `ai_context.instructions` hold rules across datasets,
  within 2,300 characters (the executor adds about 1,780, and Claude
  Code cuts at 4,096).
- A dataset built from orders names which orders it counts, in the
  model's terms, then the store report that counts the same.

## ClickHouse traits

- A `SELECT` alias shadows a column of the same name in `WHERE`: filter
  raw columns in an inner subquery.
- `ORDER BY` columns of a `MergeTree` cannot be Nullable.
- A CTE runs again at every reference. WooCommerce models mark CTEs
  `MATERIALIZED` and end with `woocommerce_query_settings()`.
- A sort over a prefix of the sorting key streams; any other sort holds
  the table in memory. A new input table's sorting key starts with the
  key the models dedupe by (`shopify_latest`).
- A `LEFT JOIN` without a match gives 0 for a non-Nullable column only
  while `join_use_nulls` is 0; the settings macros set it, and
  `tests/profiles.yml` sets 1 to prove it.
- `INSERT ... SELECT` buffers up to 2 GB on 8 cores. Settings for the
  insert go in `+query_settings` (Shopify's `dbt_project.yml`): the
  contract wraps a model in a subquery, whose `SETTINGS` never reach it.

## Development

- dbt v2 (`dbt-oss`) and v1 (`dbt-core` 1.11, `dbt-clickhouse`) give
  identical results; the GitHub release names the tested versions.
- `tests/profiles.yml` is the profile of CI and the checks; packages
  ship none. It sets LZ4: dbt v2's adapter cannot read ZSTD.
- `macros/freshness.sql` replaces dbt v2's broken `dbt source
  freshness` (dbt-labs/dbt#16714); remove it and the `dispatch` setting
  once `dbt-oss` fixes it.
