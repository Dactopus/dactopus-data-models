# The iot model

[`entities/iot.yaml`](../entities/iot.yaml) has 9 metrics, each on the
dataset whose rows it counts; a question names one as `dataset.metric`
(`devices.device_count`):

- readings: `reading_count`, `avg_value`, `min_value`, `max_value`,
  `reporting_devices`, `last_reading_time`. They break down by measure
  (`pm10`, `pm2_5`, `temperature`, `humidity`, `pressure`); the
  reading's hour, date, week and month; device, sensor and sensor type;
  and by the device fields below.
- devices: `device_count`, `last_contact_time`,
  `minutes_since_last_contact`. They break down by country, indoor or
  not, the sensor types a site has, its first and latest reading, and its
  last contact: the later of its latest report in the snapshots and its
  latest reading.

A device is a site: one place with coordinates, where a board reports
through one or more sensors. A value metric means something for one
measure at a time, so the model tells agents to filter or break down by
`readings.measure` and never to average different measures together.
Units: PM10 and PM2.5 in µg/m³, temperature in °C, relative humidity in
%, pressure in Pa.

## Limits

- **Time.** Every time is UTC, and a reading's date is its date in UTC.
  The source gives a site no time zone, and Australia alone has three,
  so a reading near local midnight falls on another date.
- **Values** are as the sensors sent them, not cleaned: humidity of 100
  in dew, dust peaks in rain and a faulty sensor's readings stay (a site
  in Australia averaged 129.9 °C over a week). The package corrects two
  things only: `nan` is no reading, and a pressure from 300 to 1,100 is
  read as hPa and converted to Pa.
- **Silence** is measured from the latest contact in the data
  (`devices.last_contact_time`), not from the clock: "silent for more
  than an hour" is an hour before it, and the agent names it and its
  age. While the snapshots run it is within minutes of now; without them
  it is the latest reading, hours old, since the archive publishes a day
  the day after. The snapshots keep no history, so the answer is exact
  only if they ran without a gap through the hour before that time.
- **Indoor sites** count in every average across devices; the model
  tells agents to say so and to offer the outdoor ones
  (`devices.is_indoor`). A site that was never in a snapshot has no
  country and no indoor flag.
- **Devices by their readings.** `devices.device_count` filtered on a
  field of `readings` (`readings.reading_date = '2026-10-19'`) counts
  each site with at least one such reading, as
  `readings.reporting_devices` does. Sites without a reading on a date
  cannot be counted: `NOT` in that filter keeps every site with a
  reading on another date
  ([dactopus-ossie-clickhouse#10](https://github.com/Dactopus/dactopus-ossie-clickhouse/issues/10)).
  Sites silent since a time are found through `devices.last_contact_at`.
- **Sensor types**: SDS011, PMS5003, BME280 and DHT22. Readings of other
  types, noise meters among them, are left out.
- **`devices_archive`**, behind the view `devices`, is rebuilt whole on
  every run (the package's [Quick start](../sources/sensor_community/README.md#quick-start), step 7).

The Sensor.Community package builds the tables the model reads:
[sources/sensor_community/README.md](../sources/sensor_community/README.md).
Several networks and installing the package: [deployment.md](deployment.md).
