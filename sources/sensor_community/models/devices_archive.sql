{{ config(materialized='table', order_by='device_id') }}
-- What the archive tells about each site with a reading: its sensor
-- types, its first and latest reading, and for a site that is not in the
-- snapshots its latest reading's coordinates. The view devices joins it
-- with the snapshots. Built whole by each run: a site's last reading
-- moves with every load.
SELECT
    r.device_id AS device_id,
    -- The types of the four the package reads among the site's readings.
    r.sensor_types AS sensor_types,
    r.first_reading_at AS first_reading_at,
    r.last_reading_at AS last_reading_at,
    -- NULL for a site in the snapshots, which give its coordinates.
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
    {# Coordinates of the sites without a snapshot, from their latest
       reading. A site never leaves the snapshots once in them
       (input.sql), so one that enters after this run has the snapshot's
       coordinates in devices. #}
    SELECT location AS device_id, argMax((lat, lon), (timestamp, lat, lon)) AS coordinates,
           coordinates.1 AS latitude, coordinates.2 AS longitude
    FROM {{ source('sensor_community_raw', 'readings') }}
    WHERE sensor_type IN {{ sensor_community_types() }}
      AND location NOT IN (SELECT location_id FROM {{ source('sensor_community_raw', 'locations') }})
    GROUP BY location
) AS f ON f.device_id = r.device_id
{{ sensor_community_query_settings('join_use_nulls = 1') }}
