{{ config(materialized='view') }}
-- One row per site, a "location" in Sensor.Community's terms (input.sql):
-- every site in the snapshots and every site with a reading. A view over
-- devices_archive and the snapshots, so a snapshot loaded after the last
-- run is in it at once: a site's last contact, country and indoor flag
-- need no build. The snapshots stay as large as the sensors (input.sql),
-- so reading them at every question is cheap; the readings are read by
-- the build only. A full join of the two reads each once.
SELECT
    -- Every row has the site on one side at least.
    assumeNotNull(coalesce(s.location_id, a.device_id)) AS device_id,
    -- Coordinates from the latest snapshot, as the source gives them (it
    -- coarsens those of sites not marked exact); a site without a snapshot
    -- has its latest reading's.
    coalesce(s.latitude, a.latitude) AS latitude,
    coalesce(s.longitude, a.longitude) AS longitude,
    s.altitude AS altitude,
    -- From the latest snapshot; NULL for a site that has not reported
    -- during one.
    nullIf(s.country, '') AS country_code,
    s.indoor AS is_indoor,
    -- The types of the four the package reads seen at the site, in the
    -- snapshots or in its readings, in alphabetical order and separated
    -- by ", " (Ossie has no array type); empty for a site with others
    -- only, whose readings the package does not read.
    arrayStringConcat(arraySort(arrayDistinct(arrayConcat(s.sensor_types, a.sensor_types))), ', ') AS sensor_types,
    a.first_reading_at AS first_reading_at,
    a.last_reading_at AS last_reading_at,
    -- The latest the network heard from the site: its latest report in
    -- the snapshots, from a sensor of any type, or its latest reading,
    -- whichever is later. Every site has one or the other.
    multiIf(a.last_reading_at IS NULL, s.last_reported_at,
            s.last_reported_at IS NULL, a.last_reading_at,
            greatest(a.last_reading_at, s.last_reported_at)) AS last_contact_at
FROM
(
    {# The latest snapshot's row, by the snapshot's time, not the load's: a
       snapshot loaded late must not undo a later one. Of its rows, the
       latest reported, then the highest sensor id, then the latest
       loaded. max() takes the site's latest report among its rows, of
       every snapshot before a merge and of each sensor's latest after
       it. #}
    SELECT
        location_id,
        argMax(latitude, v) AS latitude,
        argMax(longitude, v) AS longitude,
        argMax(altitude, v) AS altitude,
        argMax(country, v) AS country,
        argMax(indoor, v) AS indoor,
        groupUniqArrayIf(sensor_type, sensor_type IN {{ sensor_community_types() }}) AS sensor_types,
        max(reported_at) AS last_reported_at
    FROM
    (
        SELECT *, (snapshot_at, reported_at, sensor_id, loaded_at) AS v
        FROM {{ source('sensor_community_raw', 'locations') }}
    )
    GROUP BY location_id
) AS s
FULL OUTER JOIN {{ ref('devices_archive') }} AS a ON a.device_id = s.location_id
{# The view keeps this setting: a query over it gets NULL, not 0 or an
   empty string, for a site missing on one side. #}
SETTINGS join_use_nulls = 1
