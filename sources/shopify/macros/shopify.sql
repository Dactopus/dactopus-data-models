{# The latest version of each row of an input table (input.sql): the
   greatest version time, and of two loads of the same version the later. #}
{% macro shopify_latest(table, key, version='updated_at') -%}
(SELECT * FROM {{ source('shopify_raw', table) }} ORDER BY {{ version }} DESC, loaded_at DESC LIMIT 1 BY {{ key }})
{%- endmacro %}

{# Version time from which an incremental run rereads the input: the last
   one this model has seen minus the lookback. An empty table rereads
   everything: its max() is 1970-01-01, and subtracting below it wraps. #}
{% macro shopify_window_start(column) -%}
(SELECT if(count() = 0, toDateTime(0, 'UTC'), max({{ column }}) - INTERVAL {{ var('shopify_lookback_days') }} DAY) FROM {{ this }})
{%- endmacro %}
