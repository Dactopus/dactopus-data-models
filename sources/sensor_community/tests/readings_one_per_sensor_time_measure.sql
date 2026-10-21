-- A sensor gives one value of a measure at a time: the package keeps one
-- row of each sensor and time (readings.sql), and an incremental run
-- replaces a sensor-day whole.
SELECT sensor_id, measured_at, measure, count() AS rows
FROM {{ ref('readings') }}
GROUP BY sensor_id, measured_at, measure
HAVING rows > 1
