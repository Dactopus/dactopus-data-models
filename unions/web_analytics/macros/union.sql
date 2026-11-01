{# The SQL of every union, the same file in each (tests/check_contracts.py
   compares them). The union's own file, <domain>_union.sql, names its
   variable, the list of the databases it adds up, and what each database
   holds (stores, properties, networks), for the messages. #}

{# The view of one table over the databases of the variable: each
   instance's table, built by its package, its columns as schema.yml lists
   them, one SELECT per database under UNION ALL. A database whose table
   lacks a column or gives it another type than the contract fails the
   build here: UNION ALL would widen the type (Decimal(26, 8) and
   Decimal(38, 8) to Decimal(38, 8)) and the contract check would pass. #}
{% macro union_view(variable, instances) -%}
{%- set columns = model.columns.keys() | list -%}
{%- set databases = union_databases(variable, instances) -%}
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
{{ exceptions.raise_compiler_error(variable ~ ": " ~ problems | join('; ') ~ ". Build each of the " ~ instances ~ " with this release of its package (a release that changes columns needs --full-refresh).") }}
{%- endif -%}
{%- endif -%}
{%- for database in databases %}
SELECT {{ columns | join(', ') }} FROM {{ adapter.quote(database) }}.{{ adapter.quote(this.identifier) }}
{%- if not loop.last %}
UNION ALL{% endif %}
{%- endfor %}
{%- endmacro %}

{# The variable: a list of one or more database names, none of them
   twice, and not the union's own target database, whose views would
   replace the tables they read. #}
{% macro union_databases(variable, instances) -%}
{%- set databases = var(variable) -%}
{%- if databases is string or databases is not iterable or not databases
       or databases | select('string') | list | length != databases | length
       or databases | unique | list | length != databases | length -%}
{{ exceptions.raise_compiler_error(variable ~ " must be a list of the databases of the " ~ instances ~ ", each once, not " ~ databases) }}
{%- endif -%}
{%- if target.schema in databases -%}
{{ exceptions.raise_compiler_error(variable ~ " holds " ~ target.schema ~ ", the union's own target database: build the union into another") }}
{%- endif -%}
{{ return(databases) }}
{%- endmacro %}

{# The test that each label (source_id) is in one database: two instances
   built under one label would add up as one. It reads the tables of the
   databases, which the view does not tell apart. With each database's one
   label (its package's test) and each package's key test, it also makes
   every key of the Ossie model unique in the view. #}
{% macro union_distinct_source_ids(model, column_name, variable, instances) -%}
SELECT 1 FROM (
    SELECT throwIf(count() > 0, '{{ model.identifier }}: a source_id is in more than one database of {{ variable }}: give each of the {{ instances }} its own label and build it with --full-refresh') AS other
    FROM (
        SELECT {{ column_name }}
        FROM (
            {%- for database in union_databases(variable, instances) %}
            SELECT DISTINCT {{ column_name }}, {{ loop.index }} AS database FROM {{ adapter.quote(database) }}.{{ adapter.quote(model.identifier) }}
            {%- if not loop.last %} UNION ALL{% endif %}
            {%- endfor %}
        )
        GROUP BY {{ column_name }}
        HAVING count() > 1
    )
)
WHERE other != 0
{%- endmacro %}
