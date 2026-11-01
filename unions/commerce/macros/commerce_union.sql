{# The view of one table over the databases of commerce_union_databases:
   each instance's table, built by its package, its columns as schema.yml
   lists them, one SELECT per database under UNION ALL. A database whose
   table lacks a column or gives it another type than the contract fails
   the build here: UNION ALL would widen the type (Decimal(26, 8) and
   Decimal(38, 8) to Decimal(38, 8)) and the contract check would pass. #}
{% macro commerce_union() -%}
{%- set columns = model.columns.keys() | list -%}
{%- set databases = commerce_union_databases() -%}
{%- if execute -%}
{%- set found = {} -%}
{%- set listed = [] -%}
{%- for database in databases -%}
{%- do listed.append("'" ~ (database | replace("\\", "\\\\") | replace("'", "\\'")) ~ "'") -%}
{%- endfor -%}
{%- set rows = run_query("SELECT database, name, type FROM system.columns WHERE database IN (" ~ listed | join(', ') ~ ") AND table = '" ~ this.identifier ~ "'") -%}
{%- for row in rows -%}
{%- do found.update({row[0] ~ '.' ~ row[1]: row[2] | replace(' ', '')}) -%}
{%- endfor -%}
{%- set problems = [] -%}
{%- for database in databases -%}
{%- for column in columns -%}
{%- set expected = model.columns[column].data_type | replace(' ', '') -%}
{%- set actual = found.get(database ~ '.' ~ column) -%}
{%- if actual != expected -%}
{%- do problems.append(database ~ '.' ~ this.identifier ~ '.' ~ column ~ ' is ' ~ (actual or 'missing') ~ ', not ' ~ expected) -%}
{%- endif -%}
{%- endfor -%}
{%- endfor -%}
{%- if problems -%}
{{ exceptions.raise_compiler_error("commerce_union_databases: " ~ problems | join('; ') ~ ". Build each store with this release of its package (a release that changes columns needs --full-refresh).") }}
{%- endif -%}
{%- endif -%}
{%- for database in databases %}
SELECT {{ columns | join(', ') }} FROM {{ adapter.quote(database) }}.{{ adapter.quote(this.identifier) }}
{%- if not loop.last %}
UNION ALL{% endif %}
{%- endfor %}
{%- endmacro %}

{# The variable commerce_union_databases: a list of one or more
   database names, none of them twice, and not the union's own target
   database, whose views would replace the tables they read. #}
{% macro commerce_union_databases() -%}
{%- set databases = var('commerce_union_databases') -%}
{%- if databases is string or databases is not iterable or not databases
       or databases | select('string') | list | length != databases | length
       or databases | unique | list | length != databases | length -%}
{{ exceptions.raise_compiler_error("commerce_union_databases must be a list of the databases of the stores, each once, not " ~ databases) }}
{%- endif -%}
{%- if target.schema in databases -%}
{{ exceptions.raise_compiler_error("commerce_union_databases holds " ~ target.schema ~ ", the union's own target database: build the union into another") }}
{%- endif -%}
{{ return(databases) }}
{%- endmacro %}

{# Each label (source_id) is in one database: two stores built under one
   label would add up as one. The test reads the tables of the databases,
   which the view does not tell apart. #}
{% test commerce_union_distinct_source_ids(model, column_name) -%}
SELECT 1 FROM (
    SELECT throwIf(count() > 0, '{{ model.identifier }}: a source_id is in more than one database of commerce_union_databases: give each store its own label and build it with --full-refresh') AS other
    FROM (
        SELECT {{ column_name }}
        FROM (
            {%- for database in commerce_union_databases() %}
            SELECT DISTINCT {{ column_name }}, {{ loop.index }} AS database FROM {{ adapter.quote(database) }}.{{ adapter.quote(model.identifier) }}
            {%- if not loop.last %} UNION ALL{% endif %}
            {%- endfor %}
        )
        GROUP BY {{ column_name }}
        HAVING count() > 1
    )
)
WHERE other != 0
{%- endtest %}

{# The dataset's key in the Ossie model, its label first, is unique in the
   view. #}
{% test commerce_union_unique_key(model, columns) -%}
SELECT {{ columns | join(', ') }}, count() AS rows
FROM {{ model }}
GROUP BY {{ columns | join(', ') }}
HAVING rows > 1
{%- endtest %}
