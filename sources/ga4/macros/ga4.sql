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
