{# This union's names: its variable, the list of the databases it adds
   up, and what each database holds, for the messages. The SQL is in
   union.sql, the same file in every union. #}
{% macro iot_union() -%}
{{ union_view('iot_union_databases', 'networks') }}
{%- endmacro %}

{% test iot_union_distinct_source_ids(model, column_name) -%}
{{ union_distinct_source_ids(model, column_name, 'iot_union_databases', 'networks') }}
{%- endtest %}
