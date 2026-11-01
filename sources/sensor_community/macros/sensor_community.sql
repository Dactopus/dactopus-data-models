{# The sensor types the package reads (input.sql), as a SQL list. #}
{% macro sensor_community_types() -%}
('SDS011', 'PMS5003', 'BME280', 'DHT22')
{%- endmacro %}

{# Sensor-days of the input's readings loaded since an incremental run's
   window start: the latest load this model has seen minus the lookback.
   A day's file is loaded whole, and a later load of it (a day loaded
   again, a copy of a time with other values) must be weighed against the
   rows loaded before, so a run rereads whole sensor-days and replaces them
   in the model. An empty model rereads everything: its max() is
   1970-01-01, and DateTime64 goes below it without wrapping. #}
{% macro sensor_community_loaded_since() -%}
(SELECT DISTINCT sensor_id, toDate(timestamp, 'UTC') FROM {{ source('sensor_community_raw', 'readings') }}
 WHERE loaded_at >= (SELECT max(loaded_at) - INTERVAL {{ var('sensor_community_lookback_days') }} DAY FROM {{ this }}))
{%- endmacro %}

{# Settings every model's query ends with, as in the Shopify package: an
   INSERT ... SELECT buffers up to min_insert_block_size_bytes per insert
   thread before it writes a part, 2 GB on 8 cores with the defaults,
   while a full build of a year of readings is smaller than that and would
   be held in memory whole. `more` adds a model's own settings. #}
{% macro sensor_community_query_settings(more='') -%}
SETTINGS max_insert_threads = 1, min_insert_block_size_rows = 262144, min_insert_block_size_bytes = 67108864
{%- if more %}, {{ more }}{% endif %}
{%- endmacro %}

{# The label of the sensor network, which every row carries as source_id:
   the variable sensor_community_source_id, 1 to 64 of a-z, 0-9 and _. Tables of
   several deployments add up and join by it. A view over a built table
   passes on that table's. #}
{% macro sensor_community_source_id() -%}
{%- set label = var('sensor_community_source_id') | string -%}
{%- set allowed = 'abcdefghijklmnopqrstuvwxyz0123456789_' -%}
{%- set other = [] -%}
{%- for c in label -%}
{%- if c not in allowed -%}{%- do other.append(c) -%}{%- endif -%}
{%- endfor -%}
{%- if not label or label | length > 64 or other -%}
{{ exceptions.raise_compiler_error("sensor_community_source_id must be 1 to 64 characters of a-z, 0-9 and _, not '" ~ label ~ "'") }}
{%- endif -%}
CAST('{{ label }}' AS LowCardinality(String))
{%- endmacro %}

{# Every row carries the label of this build. A table built under another
   sensor_community_source_id and then run on incrementally holds both. #}
{% test sensor_community_one_source_id(model, column_name) -%}
SELECT 1 FROM (
    SELECT throwIf(count() > 0, '{{ model }} holds rows of a source_id other than {{ var("sensor_community_source_id") }}: run dbt build --full-refresh once after changing sensor_community_source_id') AS other
    FROM {{ model }}
    WHERE {{ column_name }} != {{ sensor_community_source_id() }}
)
WHERE other != 0
{%- endtest %}

{# A key of several columns is unique: a sensor gives one value of a
   measure at a time (readings). The package keeps one row of each sensor
   and time (readings.sql), and an incremental run replaces a sensor-day
   whole. #}
{% test sensor_community_unique_key(model, columns) -%}
SELECT {{ columns | join(', ') }}, count() AS rows
FROM {{ model }}
GROUP BY {{ columns | join(', ') }}
HAVING rows > 1
{%- endtest %}
