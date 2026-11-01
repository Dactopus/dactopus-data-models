{% macro ga4_param(key, type) -%}
(arrayFirst(p -> p.key = '{{ key }}', event_params)).value.{{ type }}_value
{%- endmacro %}

{# First date to rebuild on an incremental run: the last loaded date minus the
   lookback window and extra_days. An empty table rebuilds everything: its
   max() is 1970-01-01, and Date arithmetic below it wraps to 2149. #}
{% macro ga4_window_start(date_column, extra_days=0) -%}
(SELECT if(count() = 0, toDate(0), max({{ date_column }}) - {{ var('ga4_lookback_days') + extra_days }}) FROM {{ this }})
{%- endmacro %}

{# Incremental filter on the raw input. Compares the raw YYYYMMDD string, which
   sorts like the date, so the input's primary key skips older data; a filter
   on toDate(parseDateTime(event_date)) reads the whole table on every run. #}
{% macro ga4_raw_window(date_column, extra_days=0) -%}
event_date >= formatDateTime({{ ga4_window_start(date_column, extra_days) }}, '%Y%m%d')
{%- endmacro %}

{# The label of the analytics property, which every row carries as source_id:
   the variable ga4_source_id, 1 to 64 of a-z, 0-9 and _. Tables of
   several deployments add up and join by it. A view over a built table
   passes on that table's. #}
{% macro ga4_source_id() -%}
{%- set label = var('ga4_source_id') | string -%}
{%- set allowed = 'abcdefghijklmnopqrstuvwxyz0123456789_' -%}
{%- set other = [] -%}
{%- for c in label -%}
{%- if c not in allowed -%}{%- do other.append(c) -%}{%- endif -%}
{%- endfor -%}
{%- if not label or label | length > 64 or other -%}
{{ exceptions.raise_compiler_error("ga4_source_id must be 1 to 64 characters of a-z, 0-9 and _, not '" ~ label ~ "'") }}
{%- endif -%}
CAST('{{ label }}' AS LowCardinality(String))
{%- endmacro %}

{# Every row carries the label of this build. A table built under another
   ga4_source_id and then run on incrementally holds both. #}
{% test ga4_one_source_id(model, column_name) -%}
SELECT 1 FROM (
    SELECT throwIf(count() > 0, '{{ model }} holds rows of a source_id other than {{ var("ga4_source_id") }}: run dbt build --full-refresh once after changing ga4_source_id') AS other
    FROM {{ model }}
    WHERE {{ column_name }} != {{ ga4_source_id() }}
)
WHERE other != 0
{%- endtest %}
