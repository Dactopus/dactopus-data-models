{# The latest version of each row of an input table (input.sql): the
   greatest version time, and of two loads of the same version the later.
   `where` filters whole keys before the sort, so a run sorts only them. #}
{% macro shopify_latest(table, key, version='updated_at', where='true') -%}
(SELECT * FROM {{ source('shopify_raw', table) }} WHERE {{ where }} ORDER BY {{ version }} DESC, loaded_at DESC LIMIT 1 BY {{ key }})
{%- endmacro %}

{# Keys of an input table loaded since an incremental run's window start:
   the latest load this model has seen minus the lookback. Load time, not
   version time: a row delivered late, by a loader catching up or a
   backfill, carries an old updated_at but a new loaded_at. An empty model
   rereads everything: its max() is 1970-01-01, and DateTime64 goes below
   it without wrapping. #}
{% macro shopify_loaded_since(table, key='id') -%}
(SELECT {{ key }} FROM {{ source('shopify_raw', table) }}
 WHERE loaded_at >= (SELECT max(loaded_at) - INTERVAL {{ var('shopify_lookback_days') }} DAY FROM {{ this }}))
{%- endmacro %}
