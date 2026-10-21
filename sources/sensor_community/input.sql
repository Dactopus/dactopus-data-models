-- Input of the Sensor.Community package: two tables, filled from the
-- project's public data by any loader (README, Quick start). Only the
-- columns the package reads; a loader may deliver more. Sensor.Community
-- is a citizen network of air quality sensors (https://sensor.community/).
-- Its data is under the Open Data Commons Database Contents License
-- (DbCL 1.0), linked from the site's footer (checked 2026-10-18).
--
-- readings: the archive's daily CSV files (https://archive.sensor.community/,
-- one file per sensor and day, columns separated by ';'; the current year
-- as <date>/<date>_<type>_sensor_<id>.csv, earlier years as
-- <year>/<date>/<name>.csv.gz). Column names are the files' own, so a
-- file loads as it is, by header (input_format_with_names_use_header,
-- input_format_skip_unknown_fields). The files of each sensor type carry
-- only that type's measures; the package reads four types, SDS011 and
-- PMS5003 (particulate matter) and BME280 and DHT22 (temperature,
-- humidity, pressure), and skips the rows of any other type. Their
-- columns, checked on files of 2026-10-19 and 2025-10-19:
--   sds011   P1 durP1 ratioP1 P2 durP2 ratioP2
--   pms5003  P1 P2 P0
--   bme280   pressure altitude pressure_sealevel temperature humidity
--   dht22    temperature humidity
-- P1 is PM10 and P2 is PM2.5, in µg/m³ (the project's wiki,
-- https://github.com/opendata-stuttgart/meta/wiki/APIs); temperature is
-- in °C, humidity in %, pressure in Pa. The table keeps these five and
-- skips the rest on load: the SDS011's dur and ratio columns; P0, PM1,
-- empty in all 139,607 PMS5003 rows of a month of Australia; altitude
-- and pressure_sealevel, which some BME280 firmware derives from the
-- pressure, filled by 2 of Australia's 12 BME280 sensors.
-- Some firmware writes the word "unknown" for a measure it could not
-- take (a BME280's humidity, 2026-09-25); a loader inserts with
-- input_format_csv_use_default_on_bad_values and the value is NULL.
-- Other firmware writes nan (a BME280's humidity, 2026-10-16 07:32:16),
-- which loads as NaN; the package reads it as no value, like NULL.
-- The same data is also on ClickHouse's public S3 bucket by month
-- (clickhouse-public-datasets/sensors/monthly/, ending February 2023), in
-- the same columns.
--
-- locations: the API's snapshot of the last five minutes
-- (https://data.sensor.community/static/v2/data.json, or one country
-- through https://data.sensor.community/airrohr/v1/filter/country=<code>),
-- one row per sensor in the snapshot. It is the only source of a site's
-- country and indoor flag, so a loader takes a snapshot regularly and
-- appends it whole; the package reads the latest row of each site.
-- Nearly every row repeats the site's row in the snapshot before, so the
-- table is a ReplacingMergeTree: its merges keep, of each site and
-- sensor, the row of the latest snapshot, and it grows with the sensors,
-- not with time. The package picks the latest snapshot itself and
-- answers the same before a merge and after; the history of the
-- snapshots is not kept, and the package does not read it. A site is a
-- "location" in the project's terms: a place with coordinates where one
-- board reports through one or more sensors. The API asks for a
-- User-Agent that names a contact (the wiki, since 2022-11-04).
--
-- Times are UTC: the archive's timestamps carry no zone and match the
-- API's, which are UTC. Delivering a file or a snapshot twice is
-- harmless: the package reads each (sensor, time) once, and the latest
-- snapshot of each site. A file itself can carry one time twice with
-- values that differ a little (a BME280 on 2026-09-22, 13.2 and 13.1 °C
-- at 12:16:34); the package keeps the row with the lower values, the
-- same one whichever order the rows are stored in. A deployment may
-- collapse the readings' duplicates with ReplacingMergeTree ORDER BY
-- their key below; the package does not depend on either table's
-- engine. loaded_at is filled at insert time; an incremental build
-- rereads the sensor-days loaded since its last run.
--
-- The database is a query parameter, the package's
-- sensor_community_input_database:
--   clickhouse client --param_db=sensor_community_raw --multiquery < input.sql
CREATE DATABASE IF NOT EXISTS {db:Identifier};

CREATE TABLE IF NOT EXISTS {db:Identifier}.readings
(
    sensor_id UInt32,                           -- the sensor's API id (over 100 000 in 2026)
    sensor_type LowCardinality(String),         -- SDS011, PMS5003, BME280, DHT22, ...
    location UInt32,                            -- the site the sensor reports from
    lat Float64,                                -- the site's latitude, as the file gives it
    lon Float64,
    timestamp DateTime('UTC'),                  -- when the reading was taken
    P1 Nullable(Float64),                       -- PM10, µg/m³
    P2 Nullable(Float64),                       -- PM2.5, µg/m³
    temperature Nullable(Float64),              -- °C
    humidity Nullable(Float64),                 -- %
    pressure Nullable(Float64),                 -- Pa (BME280)
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row
)
ENGINE = MergeTree
ORDER BY (sensor_id, timestamp);

CREATE TABLE IF NOT EXISTS {db:Identifier}.locations
(
    location_id UInt32,                         -- location.id
    sensor_id UInt32,                           -- sensor.id
    sensor_type LowCardinality(String),         -- sensor.sensor_type.name
    latitude Float64,                           -- location.latitude
    longitude Float64,                          -- location.longitude
    altitude Nullable(Float64),                 -- location.altitude, m
    country String,                             -- location.country, ISO 3166-1 alpha-2
    indoor Bool,                                -- location.indoor
    reported_at DateTime('UTC'),                -- timestamp: the sensor's latest reading in the snapshot
    snapshot_at DateTime('UTC'),                -- when the loader took the snapshot
    loaded_at DateTime64(6, 'UTC') DEFAULT now64(6) -- when the load inserted the row
)
ENGINE = ReplacingMergeTree(snapshot_at)
ORDER BY (location_id, sensor_id);
