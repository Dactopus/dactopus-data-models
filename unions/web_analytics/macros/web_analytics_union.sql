{# This union's names: its variable, the list of the databases it adds
   up, and what each database holds, for the messages. The SQL is in
   union.sql, the same file in every union. #}
{% macro web_analytics_union() -%}
{{ union_view('web_analytics_union_databases', 'properties') }}
{%- endmacro %}

{% test web_analytics_union_distinct_source_ids(model, column_name) -%}
{{ union_distinct_source_ids(model, column_name, 'web_analytics_union_databases', 'properties') }}
{%- endtest %}
