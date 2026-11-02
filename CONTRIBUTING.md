# Contributing

Bug reports, questions about a mapping, new source packages and pull
requests are welcome. Everything in this repository is in English: models,
descriptions, SQL comments, commit messages, issues.

## Reporting a wrong number

The failure this project guards against is a model that builds, passes its
checks and returns the wrong value. If you see one, open an issue with:

- the source and entity (`sources/ga4`, `sessions`);
- the question: metrics, dimensions, filters, period;
- the number the model gives and the number you expected, and where the
  expected one comes from: the source's own interface, its documentation,
  or a hand-written query (include it).

Some differences are expected and documented: each package's README has
a section of known differences from the source's own reports, and the
field and metric descriptions in `entities/` say where the model's
definition differs.

## Setup

You need a [ClickHouse](https://clickhouse.com/docs) server,
dbt and [dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse).
Without a server at hand, the
[official Docker image](https://clickhouse.com/docs/install/docker) gives
one (the variable lets the passwordless `default` user connect over the
network):

```bash
docker run -d --name ch -p 8123:8123 -p 9000:9000 -e CLICKHOUSE_SKIP_USER_SETUP=1 clickhouse/clickhouse-server:26.9
pip install dbt-oss                     # dbt v2; or dbt-core~=1.11 with dbt-clickhouse (v1)
pip install "dactopus-ossie-clickhouse[mcp]"
```

Add the dbt profile of the README's [Quick start](README.md#quick-start)
and build a package over its fixture as the Quick start does. CI runs on
ClickHouse 26.9, and the WooCommerce package on 26.7 as well, the oldest
release it builds on; older releases are untested.

## Layout

    entities/<domain>.yaml    one Ossie model per domain (web_analytics,
                              commerce, iot): its entities, relationships
                              and metrics
    sources/<source>/         one package per source, a dbt project:
      README.md               the package's guide: loading, settings, known
                              differences from the source's own reports
      input.sql               the input tables the package accepts
      deployment.yml          what a deployment sets and reads: the Ossie
                              model, the variables for the input database,
                              the label and the time zone, the zone the
                              package fixes for its days, the tables
                              counted per day
      macros/<source>.sql     SQL the package's models share
      macros/freshness.sql    `dbt source freshness` on dbt v2, the same
                              file in every package
      models/<entity>.sql     one model per entity, named after it; a table
                              behind an entity's model that is no entity
                              itself is <entity>_<part>.sql
                              (devices_archive.sql, product_categories_all.sql)
      models/schema.yml       structural checks (dbt tests) and each
                              column's type (the dbt contract)
      models/sources.yml      the input tables as a dbt source, with their
                              freshness
      tests/                  singular dbt tests, for checks a generic
                              test cannot express
    unions/<domain>/          one union per domain, a dbt project of views
                              that add up the tables of several databases,
                              each built by a package under its own label
      deployment.yml          the Ossie model and the variable that lists
                              the databases
      macros/union.sql        the view over the databases and its test,
                              the same file in every union
      macros/<domain>_union.sql
                              the union's variable and its test's name
      models/<entity>.sql     one view per dataset of the Ossie model
      models/schema.yml       the view's columns and types (the dbt
                              contract): those the Ossie model reads, no
                              others; its tests
    tests/<source>/           hand-written input rows (fixture.sql, and
                              windows.sql for the retention windows) and
                              the numbers the model must answer over them
                              (check_numbers.py asks the questions of
                              questions.yaml, each with the derivation of
                              its numbers in comments)
      canon/                  commerce packages: the canonical tables over
      canon_windows/          fixture.sql, and over fixture.sql with
                              windows.sql, one CSV file a table
    tests/commerce/tables.sql the canonical tables of the commerce domain
                              in standard SQL, written by export_canon.py
    tests/ask_model.py        asks the questions, shared by every source
    tests/export_canon.py     writes the canonical tables of a built
                              package to the CSV files, and tables.sql
    tests/run_canon.py        loads the CSV files into an engine and asks
                              the questions of them, with no dbt
    tests/canon.py            what the two share
    tests/check_contracts.py  checks the contracts of the packages and the
                              unions against the Ossie models and each other
    tests/check_deployment.py checks the deployment.yml of each package and
                              union against it and its built tables
    tests/check_freshness.py  checks the ages `dbt source freshness` reports
    tests/check_union.py      checks a union's answers against those of the
                              databases it adds up
    tests/profiles.yml        the dbt profile CI and the checks build with;
                              a package ships none
    docs/<domain>.md          what each Ossie model answers and its limits
    docs/deployment.md        the packages in a dbt project: labels, time
                              zones, serving the models, unions
    docs/architecture.svg     the diagram, shown in the README and, with
    docs/index.html           the text for each part, on GitHub Pages;
                              update both in the change that alters what
                              they show

A package's model writes the entity's table, named after it, in the
database the deployment chooses. The entity's dataset in the domain's
Ossie model names that table without a database (an Ossie model is one
file, since relationships and metrics span entities), so one model serves
any database dactopus-ossie-clickhouse connects to, and
`dactopus-ossie-clickhouse validate --url` checks that the package delivers every
column the entity declares. A deployment picks one package per entity.

Every package declares the type of each column it writes (a dbt
contract in `models/schema.yml`), and a build stops on any other type.
The columns the entity's Ossie model reads come first in each table,
with the same types in every package of the entity: the tables of
Shopify and WooCommerce add up with `UNION ALL`.
`uv run tests/check_contracts.py` checks it.

This is one repository, not one per source. Packages map onto shared
entities, so they are released together with them under a single version.
Consumers take the subdirectories they need.

## What a source package is

A package is more than a table schema. Every pair of an entity and a
source has six parts:

| Part | Lives in | Example |
| --- | --- | --- |
| 1. Schema: row grain, keys | entity | one row per order |
| 2. Mapping from the source | package | where `refunded_total` comes from, how statuses map, what happens to currency |
| 3. Refresh strategy | package | by load time or a re-read window; the latest version of each row |
| 4. Structural checks | package | uniqueness, not-null, freshness, `refunded_total <= total` |
| 5. Field descriptions | entity | plus `ai_context` and synonyms |
| 6. Simple metrics | entity | net revenue = `total - refunded_total` |

Part 2 is where the value is. Sources differ in what a status means,
when a refund counts and when the same thing is sent twice: GA4, for one,
sends a purchase again when the thank-you page is reloaded. A package
that gets the schema right and the mapping wrong returns wrong numbers
that look plausible.

## Out of scope

- Loading data. The package READMEs give recipes; the tools are someone
  else's.
- Running queries. That is dactopus-ossie-clickhouse.
- Reconciling with the source's own reports through its API.
- Anything that needs two sources at once: attributing sessions to
  orders, matching customers across systems, cross-source marts. A union
  puts the tables of several stores side by side and matches nothing
  across them.
- API connectors (for example to the GA4 API) and Universal Analytics.

Everything here is Apache 2.0. If a file cannot be released under it, it
does not belong here.

## Authoring rules

**Format.** Ossie schema `0.2.0.dev0`, the only version the upstream
schema accepts today. Write expressions in `ANSI_SQL`; dactopus-ossie-clickhouse
also accepts `OSSIE_SQL_2026`. Mapping, refresh and checks live in the
package's dbt project, not in the Ossie files, so entities stay plain Ossie
that any Ossie tool reads. The only extension used is dactopus-ossie-clickhouse's
`CLICKHOUSE` namespace and its `dedup` key.

**The canon is selected, not designed.** A field that at least two
sources provide goes into the canonical entity. A source that has less
of it still provides it when the meaning is the same: a category with
its subcategories, where Shopify's product types have no subcategories.
While a domain has a single source (GA4 for events), a field qualifies
when its meaning does not depend on that source. Where the second source
is known but not yet packaged, the field must exist there too, checked
against its documentation. A field only one source has is not modelled
until a second source needs it. A reference domain (`iot`) is built from
one public dataset with no second source planned: a field qualifies when
any network of devices would have it with the same meaning. No canonical
field goes in "for completeness".

**Descriptions are part of the model.** Agents answer from descriptions,
synonyms and `ai_context`. Without them even strong models guess. A
one-line description is the minimum, not the target.

**Name the "obvious" choices.** Models break on what looks obvious:
- Order date: placed, paid or shipped? Store time zone or UTC?
- Customer: account, email or card?

A package states which one it uses and why.

**dactopus-ossie-clickhouse limits are rules here.**
- Joins are many-to-one only, on a declared primary or unique key, and
  each dataset has one path from the question's root.
- Two fact tables meet only on shared dimensions: their metrics in one
  question are computed apart and merged. A metric that combines both
  facts needs them in one table, so such a mart is materialized as one
  fact table.
- A metric cannot reference another metric by name; repeat the
  expression.
- No time grain or derived dimensions: declare one field per grain.
- `source` is a table name without a database, not a query: the
  deployment picks the database.

See its [model authoring guide](https://github.com/Dactopus/dactopus-ossie-clickhouse/blob/main/docs/model-authoring.md).

**Access control is not modelled.** It comes from ClickHouse grants.

## Checks before a pull request

A model that validates can still return wrong numbers. For a change to a
package or a model:

1. `dactopus-ossie-clickhouse validate <model> --url <clickhouse>/<database>`
   passes against loaded data.
2. `dbt build` of the package passes: models and their tests.
3. An incremental run over unchanged input changes nothing, and matches a
   `--full-refresh` build row for row.
4. A number the change affects matches a hand-written ClickHouse query
   over the same data. Put both queries and both results in the pull
   request.
5. `tests/<source>/check_numbers.py` passes over that source's fixture
   (CI runs it). A changed number gets a new expected value with its
   derivation in `tests/<source>/questions.yaml` (GA4 and
   Sensor.Community still list theirs in `check_numbers.py`); a new source
   behaviour gets fixture rows. Check that a
   new case fails against the old code.
6. A change that moves a canonical row of a commerce package (a column
   the model reads, a mapping, the fixture) regenerates its files:
   build the package over `fixture.sql` loaded at once (and, for
   `canon_windows`, over `windows.sql` as well), then run
   `uv run tests/export_canon.py <source>` (`--windows` for the second)
   and commit the files. `uv run tests/run_canon.py <source> --engine
   clickhouse` (`--windows`) then asks the questions of the files alone;
   CI does both. `--engine duckdb` asks them through DuckDB's community
   extension `ossie`, which refuses some questions; CI does not run it.
7. A change to descriptions, `ai_context` or model instructions changes
   what agents answer. Ask the questions it affects through
   `dactopus-ossie-clickhouse serve` (MCP), in fresh sessions, with more
   than one AI model, and compare every number in the answers with the
   hand-written queries.

```bash
dbt build --project-dir sources/ga4 --profiles-dir tests      # models and tests
dactopus-ossie-clickhouse validate entities/web_analytics.yaml --url http://127.0.0.1:8123/dactopus
uv run tests/check_contracts.py                               # column types agree across packages
uv run tests/check_deployment.py sources/ga4 --time-zone UTC  # deployment.yml against the built tables
```

Facts about ClickHouse behaviour and a source's export schema come from
running queries (`clickhouse local` or a server) or from the source's
documentation, cited next to the code, not from memory.

CI builds every package on dbt v2 and v1, first over an empty input
table, then over the package's hand-written rows
(`tests/<source>/fixture.sql`): incrementally into the empty tables, again
over unchanged input, and with `--full-refresh`. After each build
`tests/<source>/check_numbers.py` asks the model questions and compares
the answers with numbers derived by hand from those rows. Every job then
checks `deployment.yml`, the contracts against the built tables, the
Ossie model against them and `dbt source freshness`, and builds under a
label other than the package's default. The Shopify and WooCommerce jobs
also check the retention windows (`windows.sql`) and a build in two time
zones, and that the canonical tables of the build are the CSV files in
`tests/<source>/canon*`, over which `tests/run_canon.py` asks the
questions again with no dbt; the WooCommerce job runs on ClickHouse 26.7 and 26.9. The unions
job builds every package into databases of its own, builds the three
unions over them and compares each label's answers with its database's
(`tests/check_union.py`). The fixtures are small, so they do not replace
the check on real data. A job of its own validates the Ossie models of
every domain together, with no server: a deployment with several
packages serves them as one, and the executor refuses a name defined in
two files.

A job runs when a file it reads changed: its package, its entity, its
`tests/<source>/` and `tests/ask_model.py`, or what every job reads
(`ci.yml`, `tests/profiles.yml`, the `check_*.py` scripts); the filters
are in `ci.yml`. The unions job runs on a change to any package, the
validate job on a change to any entity. Documentation reaches no job. The
check `main` requires is `CI passed`, which fails when a job failed or
was cancelled and passes otherwise, also when every job was skipped.

## Adding a source package

[ROADMAP.md](ROADMAP.md) lists what is planned. Open an issue before you
start a package, so the input and the entities it maps to are agreed
first.

A package maps one source onto the canonical entities. It is a dbt
project in `sources/<source>/`, laid out as in [Layout](#layout):

- `input.sql`: the input tables the package accepts. Only the columns the
  package reads, with types from the source's official schema, not from
  one sample of it. The database is the query parameter
  `{db:Identifier}`; the models read it from a dbt variable
  (`<source>_input_database`).
- `models/<entity>.sql`: one model per entity, named after it, writing
  the table `<entity>` in the dbt target's database. The columns the
  Ossie model reads come first, with the types every package of the
  domain gives them; every table's first column is `source_id`, the
  label from `<source>_source_id` (`docs/deployment.md`). No database
  name in the code.
- `models/schema.yml`: each column's type (the dbt contract, `+contract`
  in `dbt_project.yml`) and the structural checks as dbt tests, the key
  of each table among them. Descriptions live in the Ossie model only.
- `models/sources.yml` and `macros/freshness.sql`: the input tables as a
  dbt source with their freshness; the macro file is the same in every
  package.
- `deployment.yml`: the Ossie model, the variables by their role and the
  tables counted per day. A package whose model fixes the zone of its
  days (`toDate(..., 'UTC')`) declares it as `zone`, without the role
  `time_zone`; a package whose days are in the source's zone declares
  neither. `tests/check_deployment.py` checks it.
- `README.md`: how to load the source, the package's variables, and its
  known differences from the source's own reports.
- `tests/<source>/fixture.sql` and `check_numbers.py`: hand-written rows,
  each a case the package must get right, and the numbers the model must
  answer over them, each derived in a comment. A CI job like the
  existing ones runs them.
- The domain's union (`unions/<domain>/`) reads the new package's tables
  as it reads the others', if their columns and types match the
  contract; `tests/check_contracts.py` checks it.

What the source does (what a status means, when a refund counts, when it
sends duplicates) comes from its documentation or its data, cited in a
comment next to the code that relies on it. A package adapted from a
[Fivetran dbt package](https://github.com/fivetran) says so and keeps
Fivetran's license notice. Packages that need two sources at once, such
as attributing sessions to orders, do not belong here ([Out of
scope](#out-of-scope)).

## Adding a field or metric

A field goes into a canonical entity when at least two sources provide it
([Authoring rules](#authoring-rules) has the rule while a domain has one
source). Every field and
metric gets a description, and `ai_context` synonyms where people phrase
it differently: agents answer from these, so a missing description is a
defect. A field or dataset the Ossie model starts to read goes into the
domain's union (`unions/<domain>/models/schema.yml`) in the same change,
with its type. Renaming or removing a field, metric or column, or
changing what a metric means, is a breaking change (README,
[Versioning](README.md#versioning)).

## Pull requests

Small and focused, one change each. Add an entry under `[Unreleased]` in
`CHANGELOG.md`, and say there when the change alters numbers or needs
`dbt build --full-refresh`. By submitting a contribution you agree it is
licensed under the Apache License 2.0, like the rest of the project.

## Releasing

For maintainers.

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under
   `## [X.Y.Z] - YYYY-MM-DD` with the Ossie schema version the release
   targets, and mark it if it needs a full refresh.
2. Set `version` in every `sources/*/dbt_project.yml` and
   `unions/*/dbt_project.yml` to `X.Y.Z`, and the `revision` of the
   `packages.yml` example in `docs/deployment.md` to `vX.Y.Z`.
3. Merge after CI passes, then tag the commit on `main`. A published tag
   never moves: a fix is a new version.

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "dactopus-data-models X.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title X.Y.Z --notes-file notes.md
```
