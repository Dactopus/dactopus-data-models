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
