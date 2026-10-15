{# `dbt source freshness` on dbt v2. Its default macro selects now(), a
   DateTime, which the ClickHouse driver returns as an integer, and dbt v2
   rejects every source for it (https://github.com/dbt-labs/dbt/issues/16714).
   These cast both times to DateTime64, which arrives as a timestamp; dbt v1
   gets the same ages. Remove them, and the dispatch setting the README
   gives for installed packages, once a dbt-oss release has the fix. #}
{% macro clickhouse__collect_freshness(source, loaded_at_field, filter) %}
  {% call statement('collect_freshness', fetch_result=True, auto_begin=False) -%}
    select
      toDateTime64(max({{ loaded_at_field }}), 6) as max_loaded_at,
      now64(6) as snapshotted_at
    from {{ source }}
    {% if filter %}
    where {{ filter }}
    {% endif %}
  {% endcall %}
  {{ return(load_result('collect_freshness')) }}
{% endmacro %}

{% macro clickhouse__collect_freshness_custom_sql(source, loaded_at_query) %}
  {% call statement('collect_freshness_custom_sql', fetch_result=True, auto_begin=False) -%}
  with source_query as (
    {{ loaded_at_query }}
  )
  select
    toDateTime64((select * from source_query), 6) as max_loaded_at,
    now64(6) as snapshotted_at
  {% endcall %}
  {{ return(load_result('collect_freshness_custom_sql')) }}
{% endmacro %}
