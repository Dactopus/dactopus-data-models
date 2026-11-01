{# This union's names: its variable, the list of the databases it adds
   up, and what each database holds, for the messages. The SQL is in
   union.sql, the same file in every union. #}
{% macro commerce_union() -%}
{{ union_view('commerce_union_databases', 'stores') }}
{%- endmacro %}

{% test commerce_union_distinct_source_ids(model, column_name) -%}
{{ union_distinct_source_ids(model, column_name, 'commerce_union_databases', 'stores') }}
{%- endtest %}
