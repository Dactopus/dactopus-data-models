-- Hand-written Sensor.Community rows for check_numbers.py, loaded into the
-- package input (sources/sensor_community/input.sql). Each site is a case
-- the package must get right; check_numbers.py derives the expected
-- numbers from these rows. The input database is the query parameter db,
-- as in input.sql. Ids, places and values are made up, in the shapes the
-- archive's files and the API's snapshots have; no row is copied from the
-- project's data.
--
-- Five sites (devices), their sensors and what each one tests:
--   101  SDS011 1001 and DHT22 1002, Australia; moved outdoors between the
--        first two snapshots, so only the latest row says where it is; a
--        reading a second before midnight UTC; its file of October 19
--        loaded twice; in the last snapshot, after its latest reading, so
--        heard from by the snapshots but silent by its readings
--   102  BME280 1003, New Zealand, indoors: one sensor; a time given twice
--        in one file with different temperatures; a humidity the firmware
--        could not take (the word unknown, NULL once loaded); a time with
--        nan for every measure (NaN once loaded); a reading after its
--        latest report in the snapshots, so silent by the snapshots but
--        heard from by its readings
--   103  PMS5003 1004 and SPS30 1005, Australia: three hours without a
--        reading, then silent from October 18 11:00; SPS30 is outside
--        the four types the package reads
--   104  DHT22 1006 and BME280 1008: readings, no snapshot, so no country
--        and no indoor flag; 1008's firmware sends the pressure in
--        hPa; 1006's file of October 19 loaded again with a copy of a
--        time that has a lower temperature and no humidity
--   105  DNMS (Laerm) 1007, Australia: in the snapshots, no reading of the
--        four types
--
-- Loads: the snapshot of October 18 10:00 UTC; the files of October 18,
-- loaded on October 19 at 10:30; the snapshot of October 19 10:00, loaded
-- twice; the snapshot of October 19 12:30; the files of October 19,
-- loaded on October 20 at 10:30; site 101's files of October 19 again at
-- 11:00; 1006's file of October 19 again at 11:30. Times are UTC.

-- Snapshot of October 18. The API gives a sensor several records in five
-- minutes: 1001 twice. Site 101 is indoors here, at other coordinates.
INSERT INTO {db:Identifier}.locations VALUES
-- (location_id, sensor_id, sensor_type, latitude, longitude, altitude, country, indoor,
--  reported_at, snapshot_at, loaded_at)
(101, 1001, 'SDS011',       -33.95, 151.25, 40,   'AU', true,  '2026-10-18 09:57:10', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(101, 1001, 'SDS011',       -33.95, 151.25, 40,   'AU', true,  '2026-10-18 09:59:40', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(101, 1002, 'DHT22',        -33.95, 151.25, 40,   'AU', true,  '2026-10-18 09:59:41', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(102, 1003, 'BME280',       -36.85, 174.76, NULL, 'NZ', true,  '2026-10-18 09:58:00', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(103, 1004, 'PMS5003',      -34.93, 138.6,  50,   'AU', false, '2026-10-18 09:59:00', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(103, 1005, 'SPS30',        -34.93, 138.6,  50,   'AU', false, '2026-10-18 09:59:00', '2026-10-18 10:00:00', '2026-10-18 10:00:01'),
(105, 1007, 'DNMS (Laerm)', -33.85, 151.21, 20,   'AU', false, '2026-10-18 09:58:30', '2026-10-18 10:00:00', '2026-10-18 10:00:01');

-- Files of October 18, loaded on October 19 at 10:30.
INSERT INTO {db:Identifier}.readings VALUES
-- (sensor_id, sensor_type, location, lat, lon, timestamp,
--  P1, P2, temperature, humidity, pressure, loaded_at)
(1001, 'SDS011',  101, -33.9,  151.2,  '2026-10-18 10:00:00', 10,   4,    NULL, NULL, NULL,   '2026-10-19 10:30:00'),
-- A second before midnight UTC: October 18 in UTC, 10:59:59 on October 19
-- in Sydney.
(1001, 'SDS011',  101, -33.9,  151.2,  '2026-10-18 23:59:59', 20,   8,    NULL, NULL, NULL,   '2026-10-19 10:30:00'),
(1002, 'DHT22',   101, -33.9,  151.2,  '2026-10-18 10:00:05', NULL, NULL, 18,   60,   NULL,   '2026-10-19 10:30:00'),
(1003, 'BME280',  102, -36.85, 174.76, '2026-10-18 12:00:00', NULL, NULL, 21,   40,   101000, '2026-10-19 10:30:00'),
-- The file gives 12:16:34 twice, temperatures 22.2 and then 22.1.
(1003, 'BME280',  102, -36.85, 174.76, '2026-10-18 12:16:34', NULL, NULL, 22.2, 41,   101100, '2026-10-19 10:30:00'),
(1003, 'BME280',  102, -36.85, 174.76, '2026-10-18 12:16:34', NULL, NULL, 22.1, 41,   101100, '2026-10-19 10:30:00'),
(1004, 'PMS5003', 103, -34.93, 138.6,  '2026-10-18 08:00:00', 6,    3,    NULL, NULL, NULL,   '2026-10-19 10:30:00'),
(1004, 'PMS5003', 103, -34.93, 138.6,  '2026-10-18 11:00:00', 9,    5,    NULL, NULL, NULL,   '2026-10-19 10:30:00'),
-- SPS30's file loads into the same columns; the package skips its rows.
(1005, 'SPS30',   103, -34.93, 138.6,  '2026-10-18 08:00:00', 50,   40,   NULL, NULL, NULL,   '2026-10-19 10:30:00');

-- Snapshot of October 19, delivered twice. Site 101 is outdoors now; 103
-- has gone quiet and is not in it; 104 never is.
INSERT INTO {db:Identifier}.locations VALUES
(101, 1001, 'SDS011',       -33.9,  151.2,  35,   'AU', false, '2026-10-19 09:59:20', '2026-10-19 10:00:00', '2026-10-19 10:00:01'),
(101, 1002, 'DHT22',        -33.9,  151.2,  35,   'AU', false, '2026-10-19 09:59:21', '2026-10-19 10:00:00', '2026-10-19 10:00:01'),
(102, 1003, 'BME280',       -36.85, 174.76, NULL, 'NZ', true,  '2026-10-19 09:58:10', '2026-10-19 10:00:00', '2026-10-19 10:00:01'),
(105, 1007, 'DNMS (Laerm)', -33.85, 151.21, 20,   'AU', false, '2026-10-19 09:58:40', '2026-10-19 10:00:00', '2026-10-19 10:00:01');

INSERT INTO {db:Identifier}.locations VALUES
(101, 1001, 'SDS011',       -33.9,  151.2,  35,   'AU', false, '2026-10-19 09:59:20', '2026-10-19 10:00:00', '2026-10-19 10:05:00'),
(101, 1002, 'DHT22',        -33.9,  151.2,  35,   'AU', false, '2026-10-19 09:59:21', '2026-10-19 10:00:00', '2026-10-19 10:05:00'),
(102, 1003, 'BME280',       -36.85, 174.76, NULL, 'NZ', true,  '2026-10-19 09:58:10', '2026-10-19 10:00:00', '2026-10-19 10:05:00'),
(105, 1007, 'DNMS (Laerm)', -33.85, 151.21, 20,   'AU', false, '2026-10-19 09:58:40', '2026-10-19 10:00:00', '2026-10-19 10:05:00');

-- Snapshot of October 19 12:30, as the query of 0.5.0 loaded it: 1001
-- twice, the later record second. Only site 101 is in it.
INSERT INTO {db:Identifier}.locations VALUES
(101, 1001, 'SDS011',       -33.9,  151.2,  35,   'AU', false, '2026-10-19 12:25:10', '2026-10-19 12:30:00', '2026-10-19 12:30:01'),
(101, 1001, 'SDS011',       -33.9,  151.2,  35,   'AU', false, '2026-10-19 12:29:50', '2026-10-19 12:30:00', '2026-10-19 12:30:01'),
(101, 1002, 'DHT22',        -33.9,  151.2,  35,   'AU', false, '2026-10-19 12:28:00', '2026-10-19 12:30:00', '2026-10-19 12:30:01');

-- Files of October 19, loaded on October 20 at 10:30.
INSERT INTO {db:Identifier}.readings VALUES
(1001, 'SDS011',  101, -33.9,  151.2,  '2026-10-19 00:00:01', 30,   12,   NULL, NULL, NULL,   '2026-10-20 10:30:00'),
(1002, 'DHT22',   101, -33.9,  151.2,  '2026-10-19 00:00:06', NULL, NULL, 14,   80,   NULL,   '2026-10-20 10:30:00'),
-- Humidity 100 at dew: the package does not clean values.
(1002, 'DHT22',   101, -33.9,  151.2,  '2026-10-19 06:00:00', NULL, NULL, 12,   100,  NULL,   '2026-10-20 10:30:00'),
-- The firmware wrote unknown for the humidity: NULL, no humidity reading.
(1003, 'BME280',  102, -36.85, 174.76, '2026-10-19 12:00:00', NULL, NULL, 23,   NULL, 101200, '2026-10-20 10:30:00'),
-- The firmware wrote nan for every measure: no reading, and not the
-- site's latest one.
(1003, 'BME280',  102, -36.85, 174.76, '2026-10-19 12:30:00', NULL, NULL, nan,  nan,  nan,    '2026-10-20 10:30:00'),
(1006, 'DHT22',   104, -37.81, 144.96, '2026-10-19 09:00:00', NULL, NULL, 25,   30,   NULL,   '2026-10-20 10:30:00'),
-- Pressure in hPa, 1012: the package reads 101200 Pa.
(1008, 'BME280',  104, -37.81, 144.96, '2026-10-19 09:00:00', NULL, NULL, 25,   30,   1012,   '2026-10-20 10:30:00');

-- Site 101's files of October 19 loaded again: the same rows, a later load.
INSERT INTO {db:Identifier}.readings VALUES
(1001, 'SDS011',  101, -33.9,  151.2,  '2026-10-19 00:00:01', 30,   12,   NULL, NULL, NULL,   '2026-10-20 11:00:00'),
(1002, 'DHT22',   101, -33.9,  151.2,  '2026-10-19 00:00:06', NULL, NULL, 14,   80,   NULL,   '2026-10-20 11:00:00'),
(1002, 'DHT22',   101, -33.9,  151.2,  '2026-10-19 06:00:00', NULL, NULL, 12,   100,  NULL,   '2026-10-20 11:00:00');

-- 1006's file of October 19 loaded again, its 09:00 now with temperature
-- 24 and the humidity unknown. Of the two copies the package keeps this
-- one, the lower: the reading has no humidity any more, and the humidity
-- 30 of the first copy must go with it.
INSERT INTO {db:Identifier}.readings VALUES
(1006, 'DHT22',   104, -37.81, 144.96, '2026-10-19 09:00:00', NULL, NULL, 24,   NULL, NULL,   '2026-10-20 11:30:00');
