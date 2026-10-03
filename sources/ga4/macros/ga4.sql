{% macro ga4_param(key, type) -%}
(arrayFirst(p -> p.key = '{{ key }}', event_params)).value.{{ type }}_value
{%- endmacro %}

{# First date to rebuild on an incremental run: the last loaded date minus the lookback window. #}
{% macro ga4_window_start(date_column) -%}
(SELECT max({{ date_column }}) - {{ var('ga4_lookback_days') }} FROM {{ this }})
{%- endmacro %}
