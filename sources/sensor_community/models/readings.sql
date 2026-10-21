{{ config(unique_key='sensor_id, reading_date', order_by='(sensor_id, measured_at, measure)') }}
-- One row per sensor, time and measure. A row of the archive (input.sql)
-- carries the measures of its sensor's type side by side; it gives as
-- many readings as it has measures that are not NULL, so a humidity the
-- firmware could not take is no reading. Rows of sensor types other than
-- the four the package reads are left out. Values are as the archive has
-- them, not cleaned.
SELECT
    location AS device_id,
    sensor_id,
    sensor_type,
    CAST(m.1, 'LowCardinality(String)') AS measure,
    -- PM in µg/m³, temperature in °C, humidity in %, pressure in Pa.
    assumeNotNull(m.2) AS value,
    timestamp AS measured_at,
    -- The date in UTC: a site has no time zone in the source.
    toDate(timestamp, 'UTC') AS reading_date,
    -- When the row was loaded; the next incremental run starts from it.
    loaded_at
FROM
(
    {# Of the rows for one sensor and time, two copies in one file or a
       file loaded twice, the one with the lowest values, compared in the
       order below, and of equal rows the latest load: the same row
       whichever order the rows are stored in. Sorted by the input's
       sorting key first, so ClickHouse reads it in order and sorts only
       the rows of each key. #}
    SELECT sensor_id, sensor_type, location, timestamp, P1, P2, temperature, humidity, pressure, loaded_at
    FROM {{ source('sensor_community_raw', 'readings') }}
    WHERE sensor_type IN {{ sensor_community_types() }}
    {% if is_incremental() %}
      AND (sensor_id, toDate(timestamp, 'UTC')) IN {{ sensor_community_loaded_since() }}
    {% endif %}
    ORDER BY sensor_id, timestamp, P1, P2, temperature, humidity, pressure, location, loaded_at DESC
    LIMIT 1 BY sensor_id, timestamp
)
ARRAY JOIN [('pm10', P1), ('pm2_5', P2), ('temperature', temperature), ('humidity', humidity),
            ('pressure', pressure)] AS m
WHERE m.2 IS NOT NULL
{{ sensor_community_query_settings() }}
