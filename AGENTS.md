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

    entities/            one canonical entity per Ossie YAML file
    sources/<source>/    one package per source; references entities

<!-- TBD: layout inside a package once the extension schema is settled -->

An entity holds schema (grain, keys), field descriptions and simple
metrics. A package holds the mapping from the source, the refresh
strategy and structural checks. Never put source-specific logic in an
entity.

## Model format

- Ossie schema version is pinned to `0.2.0.dev0`. Do not change it.
- Write expressions in `ANSI_SQL`.
- Parts outside the Ossie standard go in `custom_extensions` under
  <!-- TBD: namespace --> the project's namespace. The `CLICKHOUSE`
  namespace belongs to ossie-clickhouse; use it only for its `dedup` key.
- Models must work within ossie-clickhouse limits: one root dataset per
  question; many-to-one joins on a declared primary or unique key; no
  metric referencing another metric by name (repeat the expression); one
  field per time grain; `source` is `database.table`, never a query.
  Details: its [model authoring guide](https://github.com/Dactopus/ossie-clickhouse/blob/main/docs/model-authoring.md).

## Authoring rules

- A field goes into a canonical entity only when at least two sources
  provide it. A field from one source stays in that source's package.
  Do not add canonical fields "for completeness".
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

## Verifying work

A model that validates can still return wrong numbers. For a change to a
model:

1. `ossie-clickhouse validate <model> --url <clickhouse>` passes against
   loaded data.
2. Structural checks of the package pass.
   <!-- TBD: command, once the runner is chosen -->
3. A number the change affects matches a hand-written ClickHouse query
   over the same data. Show both queries and both results.

Facts about ClickHouse behaviour and the GA4 export schema come from
running queries (`clickhouse local` or a server), not from memory.

## Development

<!-- TBD: setup, runner, test and lint commands -->
