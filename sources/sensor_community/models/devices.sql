{{ config(materialized='table', order_by='device_id') }}
-- One row per site, a "location" in Sensor.Community's terms (input.sql):
-- every site in the snapshots and every site with a reading. Built whole
-- by each run: one row per site, and its last reading moves with every
-- load.
SELECT
    ids.device_id AS device_id,
    -- Coordinates from the latest snapshot, as the source gives them (it
    -- coarsens those of sites not marked exact); a site without a snapshot
    -- has its latest reading's.
    coalesce(s.latitude, f.latitude) AS latitude,
    coalesce(s.longitude, f.longitude) AS longitude,
    s.altitude AS altitude,
    -- From the latest snapshot; NULL for a site that has not reported
    -- during one.
    nullIf(s.country, '') AS country_code,
    s.indoor AS is_indoor,
    -- The types of the four the package reads seen at the site, in the
    -- snapshots or in its readings, in alphabetical order and separated
    -- by ", " (Ossie has no array type); empty for a site with others
    -- only, whose readings the package does not read.
    arrayStringConcat(arraySort(arrayDistinct(arrayConcat(s.sensor_types, r.sensor_types))), ', ') AS sensor_types,
    r.first_reading_at AS first_reading_at,
    r.last_reading_at AS last_reading_at
FROM
(
    SELECT DISTINCT location_id AS device_id FROM {{ source('sensor_community_raw', 'locations') }}
    UNION DISTINCT
    SELECT DISTINCT device_id FROM {{ ref('readings') }}
) AS ids
LEFT JOIN
(
    {# The latest snapshot's row, by the snapshot's time, not the load's: a
       snapshot loaded late must not undo a later one. Of its rows, the
       latest reported, then the highest sensor id, then the latest
       loaded. #}
    SELECT
        location_id,
        argMax(latitude, v) AS latitude,
        argMax(longitude, v) AS longitude,
        argMax(altitude, v) AS altitude,
        argMax(country, v) AS country,
        argMax(indoor, v) AS indoor,
        groupUniqArrayIf(sensor_type, sensor_type IN {{ sensor_community_types() }}) AS sensor_types
    FROM
    (
        SELECT *, (snapshot_at, reported_at, sensor_id, loaded_at) AS v
        FROM {{ source('sensor_community_raw', 'locations') }}
    )
    GROUP BY location_id
) AS s ON s.location_id = ids.device_id
LEFT JOIN
(
    SELECT device_id, groupUniqArray(sensor_type) AS sensor_types,
           min(measured_at) AS first_reading_at, max(measured_at) AS last_reading_at
    FROM {{ ref('readings') }}
    GROUP BY device_id
) AS r ON r.device_id = ids.device_id
LEFT JOIN
(
    {# Coordinates of the sites without a snapshot, from their latest
       reading. #}
    SELECT location AS device_id, argMax((lat, lon), (timestamp, lat, lon)) AS coordinates,
           coordinates.1 AS latitude, coordinates.2 AS longitude
    FROM {{ source('sensor_community_raw', 'readings') }}
    WHERE sensor_type IN {{ sensor_community_types() }}
      AND location NOT IN (SELECT location_id FROM {{ source('sensor_community_raw', 'locations') }})
    GROUP BY location
) AS f ON f.device_id = ids.device_id
{{ sensor_community_query_settings('join_use_nulls = 1') }}
