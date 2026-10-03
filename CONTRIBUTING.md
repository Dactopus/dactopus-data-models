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

Some differences are expected and documented in the model: the GA4
interface estimates session and user counts, and credits traffic sources
differently in exports from before October 2024. The field and metric
descriptions in `entities/` say where.

## Setup

You need a [ClickHouse](https://clickhouse.com/docs) server,
dbt and [ossie-clickhouse](https://github.com/Dactopus/ossie-clickhouse).
Without a server at hand, the
[official Docker image](https://clickhouse.com/docs/install/docker) gives
one (the variable lets the passwordless `default` user connect over the
network):

```bash
docker run -d --name ch -p 8123:8123 -p 9000:9000 -e CLICKHOUSE_SKIP_USER_SETUP=1 clickhouse/clickhouse-server:26.9
pip install dbt-oss                     # dbt v2; or dbt-core~=1.11 with dbt-clickhouse (v1)
pip install "ossie-clickhouse @ git+https://github.com/Dactopus/ossie-clickhouse"
```

Load the GA4 sample as the README's [Quick start](README.md#quick-start)
describes. CI runs on ClickHouse 26.9; older releases are untested.

## Checks before a pull request

[AGENTS.md](AGENTS.md#verifying-work) has the full list. For a change to a
package or a model:

```bash
dbt build --project-dir sources/ga4 --profiles-dir sources/ga4      # models and tests
ossie-clickhouse validate entities/web_analytics.yaml --url http://127.0.0.1:8123
```

An incremental run over unchanged input must change nothing and match a
`--full-refresh` build row for row. A number the change affects must match
a hand-written ClickHouse query over the sample; put both queries and
both results in the pull request.

CI builds every package on dbt v2 and v1 over an empty input table and
validates the models. It catches SQL, schema and model errors, not wrong
numbers: those need the sample.

## Adding a source package

A package maps one source onto the canonical entities. It is a dbt
project in `sources/<source>/`:

- `input.sql`: the input table the package accepts. Only the columns the
  package reads, with types from the source's official schema, not from
  one sample of it.
- `models/<entity>.sql`: one model per entity, named after it, writing
  `dactopus.<entity>`. The columns are the entity's fields.
- `models/schema.yml`: structural checks as dbt tests. Descriptions live
  in the Ossie model only.

What the source does (what a status means, when a refund counts, when it
sends duplicates) comes from its documentation or its data, cited in a
comment next to the code that relies on it. A package adapted from a
[Fivetran dbt package](https://github.com/fivetran) says so and keeps
Fivetran's license notice. Packages that need two sources at once, such
as attributing sessions to orders, do not belong here; see the README.

## Adding a field or metric

A field goes into a canonical entity when at least two sources provide it
(AGENTS.md has the rule while a domain has one source). Every field and
metric gets a description, and `ai_context` synonyms where people phrase
it differently: agents answer from these, so a missing description is a
defect. Renaming or removing a field, metric or column, or changing what a
metric means, is a breaking change (README, [Versioning](README.md#versioning)).

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
2. Set `version` in every `sources/*/dbt_project.yml` to `X.Y.Z`.
3. Merge after CI passes, then tag the commit on `main`:

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "dactopus-data-models X.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title X.Y.Z --notes-file notes.md
```
