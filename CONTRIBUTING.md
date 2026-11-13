# Contributing

Bug reports, questions about a mapping, new source packages and pull
requests are welcome. Everything in this repository is in English.
Questions about using it and ideas go to
[Discussions](https://github.com/orgs/Dactopus/discussions); issues are
for bugs and concrete changes.

## Reporting a wrong number

The failure this project guards against is a model that builds, passes
its checks and returns the wrong value. If you see one, open an issue
with:

- the source and entity (`sources/ga4`, `sessions`);
- the question: metrics, dimensions, filters, period;
- the number the model gives, the number you expected, and where the
  expected one comes from: the source's interface, its documentation, or
  a hand-written query (include it).

Some differences are expected: each package's README lists its known
differences from the source's reports, and the descriptions in
`entities/` say where a definition differs.

## Setup

You need a [ClickHouse](https://clickhouse.com/docs) server, dbt,
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse)
and [uv](https://docs.astral.sh/uv/), which runs the checks. Without a
server at hand, the
[official Docker image](https://clickhouse.com/docs/install/docker)
gives one (the variable lets the passwordless `default` user connect
over the network):

```bash
docker run -d --name ch -p 8123:8123 -p 9000:9000 -e CLICKHOUSE_SKIP_USER_SETUP=1 clickhouse/clickhouse-server:26.8
pip install dbt-oss                     # dbt v2; or dbt-core~=1.11.0 with dbt-clickhouse (v1)
pip install "dactopus-ossie-clickhouse[mcp]" uv
```

Add the dbt profile of the README's [Quick start](README.md#quick-start)
and build a package over its fixture as the Quick start does. CI runs
on ClickHouse 26.8, the LTS release, and the unions job on the latest,
26.10; older releases are untested.

## Layout

    entities/<domain>.yaml    one Ossie model per domain: web_analytics, commerce, iot
    sources/<source>/         one package per source, a dbt project
      README.md               loading, variables, known differences from the source's reports
      input.sql               the input tables the package accepts
      deployment.yml          the Ossie model, the variables by role, the tables counted per day
      macros/<source>.sql     SQL the package's models share
      macros/freshness.sql    `dbt source freshness` on dbt v2 (same file in every package)
      macros/settings.sql     the settings guard (same file in every package)
      models/<entity>.sql     one model per entity; a helper table is <entity>_<part>.sql
      models/schema.yml       column types (the dbt contract) and structural tests
      models/sources.yml      the input tables as a dbt source, with freshness
      tests/                  singular dbt tests
    unions/<domain>/          views that add up the tables of several databases
      macros/union.sql        the view and its test (same file in every union)
      models/schema.yml       the columns the Ossie model reads, with types
    evals/                    questions for an agent over your build (evals/README.md)
    tests/<source>/           fixture.sql, check_numbers.py; Shopify and WooCommerce
                              also windows.sql, questions.yaml and canon*/ (CSV tables)
    tests/commerce/tables.sql the canonical commerce tables in standard SQL
    tests/check_*.py          contracts, deployment.yml, freshness, settings, unions,
                              evals, the grader, the changelog
    tests/export_canon.py     writes a built package's tables to canon*/
    tests/run_canon.py        asks the questions of the CSV files, with no dbt
    tests/reach.py            which CI jobs a change reaches
    tests/profiles.yml        the dbt profile of CI and the checks
    docs/<domain>.md          what each Ossie model answers and its limits
    docs/deployment.md        packages in a dbt project, labels, time zones, serving, unions
    docs/architecture.svg     the diagram, and with its text on GitHub Pages
    docs/index.html           (change both together)

A package's model writes the entity's table in the database the
deployment chooses; the Ossie model names it without a database, so one
model serves any database dactopus-ossie-clickhouse connects to. Every
package declares the type of each column it writes, and the columns the
Ossie model reads come first, in the order it reads them, with the same
types in every package of the domain, so the tables of Shopify and
WooCommerce add up with `UNION ALL`. Packages and entities are released
together under one version.

## What a source package is

Every pair of an entity and a source has six parts:

| Part | Lives in | Example |
| --- | --- | --- |
| 1. Schema: row grain, keys | entity | one row per order |
| 2. Mapping from the source | package | where `refunded_total` comes from, how statuses map, what happens to currency |
| 3. Refresh strategy | package | by load time or a re-read window; the latest version of each row |
| 4. Structural checks | package | uniqueness, not-null, freshness, `refunded_total <= total` |
| 5. Field descriptions | entity | plus `ai_context` and synonyms |
| 6. Simple metrics | entity | net revenue = `total - refunded_total` |

Sources differ in what a status means, when a refund counts and when
the same thing is sent twice (GA4 sends a purchase again when the
thank-you page is reloaded). A package with the right schema and a wrong
mapping returns wrong numbers that look plausible.

## Out of scope

- Loading data. The package READMEs give recipes; the tools are someone
  else's.
- Running queries. That is dactopus-ossie-clickhouse.
- Reconciling with the source's own reports through its API.
- Anything that needs two sources at once: attributing sessions to
  orders, matching customers across systems, cross-source marts. A union
  puts the tables of several stores side by side and matches nothing.
- API connectors (for example to the GA4 API) and Universal Analytics.

Everything here is Apache 2.0; a file that cannot be released under it
does not belong here.

## Authoring rules

- **Format.** Ossie schema `0.3.0.dev0`, the only version upstream
  accepts. Expressions in `sql` (`OSSIE_SQL_2026`); `dialects` only for
  a vendor variant. Mapping, refresh and checks live in the package, so
  entities stay plain Ossie. The only extension allowed is
  dactopus-ossie-clickhouse's `CLICKHOUSE` namespace and its `dedup`
  key; the models use none.
- **The canon.** A field that two sources provide goes in, also when one
  has less of it with the same meaning (a category with subcategories,
  where Shopify's product types have none). With one source, a field
  qualifies when its meaning does not depend on it, and where the second
  source is known, it must exist there too. A reference domain (`iot`)
  takes a field any network of devices would have. Nothing goes in "for
  completeness".
- **Descriptions.** Agents answer from descriptions, synonyms and
  `ai_context`; without them even strong models guess. One line is the
  minimum.
- **Model instructions.** `ai_context.instructions` hold rules across
  datasets: labels, currencies, time zones, which rows the metrics
  count, a default meaning of a common word. A rule about one dataset,
  field or metric goes in its description, never in both. The
  instructions stay within 2,300 characters: the executor adds a
  preamble of about 1,780, and Claude Code cuts a server's instructions
  at 4,096 (`tests/check_contracts.py` checks it).
- **Obvious choices.** Order date: placed, paid or shipped, store time
  zone or UTC? Customer: account, email or card? A package states which
  and why.
- **Which rows a dataset counts.** A dataset built from orders states
  which orders it counts, in the model's terms (`orders.status`,
  `orders.in_sales_reports`, a date), then names the store report that
  counts the same. Where the stores' reports differ, the description
  says so.
- **Access control** comes from ClickHouse grants; the models carry
  none.

The executor's limits are rules here
([model authoring guide](https://github.com/Dactopus/dactopus-ossie-clickhouse/blob/main/docs/model-authoring.md)):

- joins are many-to-one on a declared key, one path to each dataset;
- two fact tables meet only on shared dimensions; a metric combining
  both needs them materialized as one fact table;
- a metric reads one dataset and sits in its `metrics`; the model has
  none of its own, and a dataset that needs another's column carries it
  (`order_lines.in_sales_reports`);
- no metric references another; no time grain or derived dimensions;
- `source` is a table name without a database.

## Checks before a pull request

A model that validates can still return wrong numbers. For a change to a
package or a model:

1. `dactopus-ossie-clickhouse validate` passes against loaded data.
2. `dbt build` of the package passes.
3. An incremental run over unchanged input changes nothing and matches a
   `--full-refresh` build row for row.
4. A number the change affects matches a hand-written ClickHouse query;
   both queries and results go in the pull request.
5. `tests/<source>/check_numbers.py` passes. A changed number gets a new
   expected value with its derivation (`questions.yaml`, or
   `check_numbers.py` at GA4 and Sensor.Community); a new behaviour gets
   fixture rows and a case that fails on the old code.
6. A change that moves a canonical row of a commerce package rebuilds
   the package over `fixture.sql` (and `windows.sql` for
   `canon_windows`), runs `uv run tests/export_canon.py <source>
   [--windows]`, commits the files, and `uv run tests/run_canon.py
   <source> --engine clickhouse` passes. `--engine duckdb` goes through
   DuckDB's `ossie` extension, which refuses some questions; CI skips it.
7. A change to descriptions, `ai_context` or instructions: ask the
   questions it affects through `dactopus-ossie-clickhouse serve`, in
   fresh sessions with more than one AI model, and compare every number
   with hand-written queries.
8. A change the questions of `evals/<domain>.yaml` read passes `uv run
   tests/check_evals.py` (`<domain> --from <database>` for GA4 and
   Sensor.Community); a change to `evals/grade.py` passes `uv run
   tests/check_grade.py` with a case for it.

```bash
dbt build --project-dir sources/ga4 --profiles-dir tests
dactopus-ossie-clickhouse validate entities/web_analytics.yaml --url http://127.0.0.1:8123/dactopus
uv run tests/check_contracts.py
uv run tests/check_deployment.py sources/ga4 --time-zone UTC
```

Facts about ClickHouse and a source's export schema come from running
queries or from the source's documentation, cited next to the code.

### What CI runs

- Every package on dbt v2 and v1, over an empty input, then over its
  fixture: incremental, again over unchanged input, and full refresh,
  with `check_numbers.py` between builds. Then `deployment.yml`, the
  contracts and the Ossie model against the built tables, freshness, a
  build under another label, and `tests/check_settings.py` for each
  guarded variable. Shopify and WooCommerce add the retention windows,
  a build in two time zones and the `canon*` files.
- The unions job builds every package on the latest ClickHouse, the
  three unions over them, and compares answers (`tests/check_union.py`),
  also for a user who may read the unions only.
- The validate job checks the Ossie models of every domain together.

A job runs when a file it reads changed (filters in `ci.yml`); a change
of text alone (descriptions, `ai_context`, a `version:` line, docs)
reaches no package job (`tests/reach.py`). `main` requires `CI passed`,
which fails only when a job failed or was cancelled. The fixtures are
small and do not replace a check on real data.

## Adding a source package

[ROADMAP.md](ROADMAP.md) lists what is planned. Open an issue before you
start, so the input and the entities are agreed first. A package is a
dbt project in `sources/<source>/` laid out as in [Layout](#layout):

- `input.sql`: only the columns the package reads, with types from the
  source's official schema; the database is the query parameter
  `{db:Identifier}`, read by the models from `<source>_input_database`.
- `models/<entity>.sql`: `source_id` first, from `<source>_source_id`,
  tested by `<source>_one_source_id`; no database name in the code.
- `models/schema.yml`: the contract and the structural tests, the key of
  each table among them. Descriptions live in the Ossie model only.
- `macros/settings.sql` and the `+meta` of `dbt_project.yml`, for an
  incremental model or a time zone: each variable in
  `meta.guarded_vars` with its default when built rows depend on it
  (the `time_zone` and `source_id` roles always), otherwise in
  `meta.free_vars`. A release that starts to guard a variable keeps its
  default.
- `deployment.yml`: a package whose days are in a fixed zone declares
  `zone`; one in the source's zone declares neither.
- `README.md`, `tests/<source>/fixture.sql` and `check_numbers.py`, and a
  CI job like the others. The domain's union reads the new tables when
  their columns match the contract.

What the source does comes from its documentation or its data, cited
next to the code. A package adapted from a
[Fivetran dbt package](https://github.com/fivetran) says so and keeps
Fivetran's license notice.

## Adding a field or metric

Every field and metric gets a description, and `ai_context` synonyms
where people phrase it differently. A field the Ossie model starts to
read goes into the domain's union `schema.yml` in the same change.
Renaming or removing a field, metric or column, or changing what a
metric means, is a breaking change ([Versioning](README.md#versioning)).

## Pull requests

Small and focused. Update the documentation the change affects in the
same pull request; documentation states the current state, and history
lives in `CHANGELOG.md` and `UPGRADING.md` only. A breaking change
([Versioning](README.md#versioning)), or one a deployment must act on
(`dbt build --full-refresh`, an input column, a grant), adds its steps
under `## Unreleased` in `UPGRADING.md`. Leave `CHANGELOG.md` alone: it
is written at release. By
submitting a contribution you agree it is licensed under the Apache
License 2.0.

## Releasing

For maintainers.

1. Write the release's section of `CHANGELOG.md` from the pull requests
   merged since the last tag, in [Common
   Changelog](https://common-changelog.org): `## [X.Y.Z] - YYYY-MM-DD`
   linked to the GitHub release; groups Changed, Added, Removed, Fixed,
   in that order; one line per change, in the imperative, with its pull
   request; breaking changes first in their group, as `**Breaking:**`.
   Leave out what changes nothing for a deployment or a model's user,
   such as CI and contributor docs. A release with steps in
   `UPGRADING.md` opens with one sentence in italics that links to
   them, and there `## Unreleased` becomes `## X.Y.Z`.
   `tests/check_changelog.py` checks the form.
2. Set `version` in every `sources/*/dbt_project.yml` and
   `unions/*/dbt_project.yml`, and the `revision` in
   `docs/deployment.md`, to the new version.
3. Merge after CI passes, then tag the commit on `main`. A published tag
   never moves. The release's notes (`notes.md`) are its `CHANGELOG.md`
   section without the heading, then one line: the Ossie schema version
   and the versions of dactopus-ossie-clickhouse, dbt and ClickHouse the
   release was tested with.

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "dactopus-data-models X.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title X.Y.Z --notes-file notes.md
```
