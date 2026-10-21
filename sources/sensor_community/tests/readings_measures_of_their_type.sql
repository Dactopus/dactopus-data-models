-- Each sensor type measures its own quantities (input.sql): SDS011 and
-- PMS5003 particulate matter, BME280 temperature, humidity and pressure,
-- DHT22 temperature and humidity. A measure of another type means a file
-- was loaded into the wrong columns.
SELECT sensor_type, measure, count() AS rows
FROM {{ ref('readings') }}
WHERE NOT (sensor_type IN ('SDS011', 'PMS5003') AND measure IN ('pm10', 'pm2_5')
           OR sensor_type = 'BME280' AND measure IN ('temperature', 'humidity', 'pressure')
           OR sensor_type = 'DHT22' AND measure IN ('temperature', 'humidity'))
GROUP BY sensor_type, measure
