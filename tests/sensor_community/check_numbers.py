"""Ask the iot model questions over tests/sensor_community/fixture.sql and
compare the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the
fixture into one database (the query parameter db) and building the
Sensor.Community package over it:

    clickhouse client --param_db=sensor_community_input --multiquery < sources/sensor_community/input.sql
    clickhouse client --param_db=sensor_community_input --multiquery < tests/sensor_community/fixture.sql
    dbt build --project-dir sources/sensor_community --profiles-dir sources/sensor_community \
        --vars '{sensor_community_input_database: sensor_community_input}'
    python3 tests/sensor_community/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus.

Readings in the fixture, one per sensor, time and measure, times in UTC:
    site 101  SDS011 1001  October 18 10:00 pm10 10, pm2_5 4; 23:59:59
                           pm10 20, pm2_5 8; October 19 00:00:01 pm10 30,
                           pm2_5 12
              DHT22 1002   October 18 10:00:05 temperature 18, humidity
                           60; October 19 00:00:06 14 and 80, 06:00 12
                           and 100
    site 102  BME280 1003  October 18 12:00 temperature 21, humidity 40,
                           pressure 101000; 12:16:34 22.1, 41, 101100;
                           October 19 12:00 23, no humidity, 101200
    site 103  PMS5003 1004 October 18 08:00 pm10 6, pm2_5 3; 11:00 9 and 5
    site 104  DHT22 1006   October 19 09:00 temperature 25, humidity 30
26 readings: humidity 6, pm10 5, pm2_5 5, pressure 3, temperature 7. Left
out: the second copy of 12:16:34 (temperature 22.2: of two rows for one
time the package keeps the one with the lower values), the repeated load
of 101's October 19 (6 more), SPS30 1005's row (pm10 50, pm2_5 40) and
102's October 19 12:30, nan for all three measures (3 more, and every
average of those measures NaN; 102's latest reading would be 12:30).

Sites: 101 Australia, outdoors in the latest snapshot (indoors in the
earlier one); 102 New Zealand, indoors; 103 Australia, outdoors, silent
from October 18 11:00; 104 no snapshot, so no country and no indoor flag;
105 Australia, outdoors, a noise sensor only, no reading.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check  # noqa: E402

MODEL = "entities/iot.yaml"

CASES = [
    # Each measure on its own; a value metric means nothing across
    # measures. temperature: 18 + 14 + 12 (101) + 21 + 22.1 + 23 (102) + 25
    # (104) = 135.1 over 7; with both copies of 12:16:34 it would be 157.3
    # over 8, with the first copy kept 135.2 over 7. humidity: 60 + 80 +
    # 100 + 40 + 41 + 30 = 351 over 6, 102's unknown not a reading.
    # pm10: 10 + 20 + 30 + 6 + 9 = 75 over 5 (125 over 6 with SPS30's 50).
    # pm2_5: 4 + 8 + 12 + 3 + 5 = 32 over 5. pressure: 101000 + 101100 +
    # 101200 over 3, in Pa. The repeated load of October 19 would add
    # pm10 30, pm2_5 12, temperature 14 and 12, humidity 80 and 100.
    (["-m", "reading_count", "-m", "avg_value", "-m", "min_value", "-m", "max_value",
      "-d", "readings.measure", "-o", "readings.measure"],
     [{"measure": "humidity", "reading_count": 6, "avg_value": 58.5, "min_value": 30, "max_value": 100},
      {"measure": "pm10", "reading_count": 5, "avg_value": 15, "min_value": 6, "max_value": 30},
      {"measure": "pm2_5", "reading_count": 5, "avg_value": 6.4, "min_value": 3, "max_value": 12},
      {"measure": "pressure", "reading_count": 3, "avg_value": 101100, "min_value": 101000,
       "max_value": 101200},
      {"measure": "temperature", "reading_count": 7, "avg_value": 135.1 / 7, "min_value": 12,
       "max_value": 25}]),
    # 26 readings from sites 101 to 104; 105 has none. 32 with the repeated
    # load, 29 with both copies of 12:16:34, 28 with SPS30.
    (["-m", "reading_count", "-m", "reporting_devices"],
     [{"reading_count": 26, "reporting_devices": 4}]),
    # By the date in UTC. October 18: 101 6 (two SDS011 rows, one DHT22),
    # 102 6, 103 4; October 19: 101 6, 102 2, 104 2. A device reports on a
    # date when it has a reading then: 101, 102, 103 and 101, 102, 104.
    (["-m", "reading_count", "-m", "reporting_devices", "-d", "readings.reading_date",
      "-o", "readings.reading_date"],
     [{"reading_date": "2026-10-18", "reading_count": 16, "reporting_devices": 3},
      {"reading_date": "2026-10-19", "reading_count": 10, "reporting_devices": 3}]),
    # PM2.5 by day: October 18 4 + 8 + 3 + 5 over 4, October 19 12. 101's
    # reading at 23:59:59 UTC is October 19 in Sydney; by Sydney's dates the
    # days would be 4 and 10.
    (["-m", "avg_value", "-f", "readings.measure = 'pm2_5'", "-d", "readings.reading_date",
      "-o", "readings.reading_date"],
     [{"reading_date": "2026-10-18", "avg_value": 5}, {"reading_date": "2026-10-19", "avg_value": 12}]),
    # The hour from 12:00 on October 18: 102's 12:00:00 and 12:16:34, three
    # measures each (9 with both copies of 12:16:34).
    (["-m", "reading_count", "-f", "readings.reading_hour = '2026-10-18 12:00:00'"],
     [{"reading_count": 6}]),
    # Average temperature by device: 101 (18 + 14 + 12) / 3, 102 (21 + 22.1
    # + 23) / 3, 104 25. On October 19 alone: 101 (14 + 12) / 2, 102 23,
    # 104 25.
    (["-m", "avg_value", "-f", "readings.measure = 'temperature'", "-d", "readings.device_id",
      "-o", "readings.device_id"],
     [{"device_id": 101, "avg_value": 44 / 3}, {"device_id": 102, "avg_value": 66.1 / 3},
      {"device_id": 104, "avg_value": 25}]),
    (["-m", "avg_value", "-f", "readings.measure = 'temperature'", "-f", "readings.reading_date = '2026-10-19'",
      "-d", "readings.device_id", "-o", "readings.device_id"],
     [{"device_id": 101, "avg_value": 13}, {"device_id": 102, "avg_value": 23},
      {"device_id": 104, "avg_value": 25}]),
    # By sensor type: BME280 3 + 3 + 2, DHT22 2 + 4 (1002) + 2 (1006),
    # PMS5003 4, SDS011 6. SPS30 is not there.
    (["-m", "reading_count", "-d", "readings.sensor_type", "-o", "readings.sensor_type"],
     [{"sensor_type": "BME280", "reading_count": 8}, {"sensor_type": "DHT22", "reading_count": 8},
      {"sensor_type": "PMS5003", "reading_count": 4}, {"sensor_type": "SDS011", "reading_count": 6}]),
    # The latest reading of each device: 101 October 19 06:00 (DHT22), 102
    # October 19 12:00, 103 October 18 11:00, 104 October 19 09:00.
    (["-m", "last_reading_time", "-d", "readings.device_id", "-o", "readings.device_id"],
     [{"device_id": 101, "last_reading_time": "2026-10-19 06:00:00"},
      {"device_id": 102, "last_reading_time": "2026-10-19 12:00:00"},
      {"device_id": 103, "last_reading_time": "2026-10-18 11:00:00"},
      {"device_id": 104, "last_reading_time": "2026-10-19 09:00:00"}]),
    # Silent for more than an hour at 12:00 on October 19, the fixture's
    # latest reading: 101, 103 and 104. 105 has never reported a reading,
    # so it has no last reading to compare.
    (["-m", "device_count", "-f", "devices.last_reading_at < '2026-10-19 11:00:00'"],
     [{"device_count": 3}]),
    # Five devices: the sites in the snapshots and in the readings. Country
    # and indoor flag from each site's latest snapshot row: 101 is outdoors
    # (indoors by its earlier snapshot, which would make it 2 and 2); 104
    # has no snapshot.
    (["-m", "device_count", "-d", "devices.country_code", "-o", "devices.country_code"],
     [{"country_code": "AU", "device_count": 3}, {"country_code": "NZ", "device_count": 1},
      {"country_code": None, "device_count": 1}]),
    (["-m", "device_count", "-d", "devices.is_indoor", "-o", "devices.is_indoor"],
     [{"is_indoor": False, "device_count": 3}, {"is_indoor": True, "device_count": 1},
      {"is_indoor": None, "device_count": 1}]),
    # Readings by their device's flag: outdoor temperature is 101's, indoor
    # 102's, and 104's has no flag.
    (["-m", "avg_value", "-f", "readings.measure = 'temperature'", "-d", "devices.is_indoor",
      "-o", "devices.is_indoor"],
     [{"is_indoor": False, "avg_value": 44 / 3}, {"is_indoor": True, "avg_value": 66.1 / 3},
      {"is_indoor": None, "avg_value": 25}]),
]


if __name__ == "__main__":
    check(MODEL, CASES)
