{{ config(materialized='table', order_by='device_id') }}
-- What the archive tells about each site with a reading: its sensor
-- types, its first and latest reading, and its coordinates in its
-- latest row in the archive. The view devices joins it with the
-- snapshots, whose coordinates it prefers. Built whole by each run: a
-- site's last reading moves with every load.
SELECT
    r.device_id AS device_id,
    -- The types of the four the package reads among the site's readings.
    r.sensor_types AS sensor_types,
    r.first_reading_at AS first_reading_at,
    r.last_reading_at AS last_reading_at,
    f.latitude AS latitude,
    f.longitude AS longitude
FROM
(
    SELECT device_id, groupUniqArray(sensor_type) AS sensor_types,
           min(measured_at) AS first_reading_at, max(measured_at) AS last_reading_at
    FROM {{ ref('readings') }}
    GROUP BY device_id
) AS r
LEFT JOIN
(
    {# Every site's coordinates in its latest row, whether it is in the
       snapshots or not: devices takes them for a site the snapshots do
       not have, at build time or later. The row may hold no reading (nan
       for every measure): the board was at the site when it sent it, so
       it gives the site's latest known place. #}
    SELECT location AS device_id, argMax((lat, lon), (timestamp, lat, lon)) AS coordinates,
           coordinates.1 AS latitude, coordinates.2 AS longitude
    FROM {{ source('sensor_community_raw', 'readings') }}
    WHERE sensor_type IN {{ sensor_community_types() }}
    GROUP BY location
) AS f ON f.device_id = r.device_id
{{ sensor_community_query_settings('join_use_nulls = 1') }}
