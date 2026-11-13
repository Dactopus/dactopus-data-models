# Sensor.Community package

Maps the readings and the sensor registry of
[Sensor.Community](https://sensor.community/), a citizen network of air
quality sensors, onto the `iot` entities `devices` and `readings`. `iot`
is the reference domain, built from this one public dataset. What the
model answers and its limits: [docs/iot.md](../../docs/iot.md).
Installing the package in a dbt project and several networks:
[docs/deployment.md](../../docs/deployment.md).

## Quick start

Over 17,000 sensors report particulate matter, temperature, humidity
and pressure every few minutes; registry and readings are open data
(Open Data Commons [DbCL 1.0](https://opendatacommons.org/licenses/dbcl/1-0/),
linked from the site's footer). The package loads one country at a
time; the examples take Australia (`AU`): 36 sites, 66 sensors in
October 2026.
You need ClickHouse, dbt, dactopus-ossie-clickhouse and
[uv](https://docs.astral.sh/uv/), as in the README's [Quick start](../../README.md#quick-start).

1. **Load** the input tables
   [`sources/sensor_community/input.sql`](input.sql). They have no
   label; their database and the label are dbt variables
   ([Variables](#variables)).

   ```bash
   clickhouse client --param_db=sensor_community_raw --multiquery < sources/sensor_community/input.sql
   ```

2. **Snapshot** the country's sensors, which ClickHouse reads from the
   API itself. Nothing else carries the country, so the snapshot is the
   registry.

   - The API returns every sensor that reported in the last five
     minutes, with its site's coordinates, country and indoor flag, so
     a sensor enters the registry once it reports during a snapshot.
   - The API asks every client for a `User-Agent` that names a contact
     ([the project's wiki](https://github.com/opendata-stuttgart/meta/wiki/APIs));
     put yours in the query below.

   ```sql
   INSERT INTO sensor_community_raw.locations (location_id, sensor_id, sensor_type, latitude, longitude, altitude,
       country, indoor, reported_at, snapshot_at)
   SELECT location.id, sensor.id, argMax(sensor.sensor_type.name, t),
          argMax(toFloat64(location.latitude), t), argMax(toFloat64(location.longitude), t),
          argMax(toFloat64OrNull(location.altitude), t), argMax(location.country, t), argMax(location.indoor = 1, t),
          max(t), now('UTC')
   FROM
   (
       SELECT *, parseDateTimeBestEffort(timestamp, 'UTC') AS t
       FROM url('https://data.sensor.community/airrohr/v1/filter/country=AU',
                headers('User-Agent' = 'dactopus-data-models loader (https://github.com/Dactopus)'), JSONEachRow,
                'location Tuple(id UInt32, country String, indoor UInt8, latitude String, longitude String, altitude Nullable(String)),
                 sensor Tuple(id UInt32, sensor_type Tuple(id UInt32, name String, manufacturer String)), timestamp String')
   )
   GROUP BY location.id, sensor.id
   ```

   Run it every five minutes (cron or any scheduler). Each run appends
   one row per sensor, its latest record (the API gives several in five
   minutes); the package reads each site's latest row.

   - A snapshot reaches the model with no build: it gives each site's
     last contact (`devices.last_contact_at`), country and indoor flag.
   - Once merged, the table keeps only each sensor's latest snapshot
     (`input.sql`): it stays the size of the country's sensors, with no
     history.
   - The snapshots also tell a sensor gone quiet from one that never
     existed.
   - Several countries go in one query (`country=AU,NZ`); the whole
     network is `https://data.sensor.community/static/v2/data.json`,
     17,500 rows.

3. **Load the history.** The archive publishes a CSV file per sensor
   and day, all of a day at once by 10:00 UTC the day after; a published
   file does not change. Save the script below as
   `load_sensor_community.py` and run it with ClickHouse's HTTP URL, the
   input database, the country and the first and last day:

   ```bash
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU 2025-10-20 2026-10-19
   ```

   The script:

   - fetches each snapshot sensor's file for each day (four at a time;
     an indoor sensor's has the suffix `_indoor`, earlier years are
     gzipped) and inserts a day at a time: about 20 seconds per day of
     Australia, two hours for a year;
   - loads only days the archive has published whole, and stops before
     a later one;
   - sends the `User-Agent` from `SENSOR_COMMUNITY_AGENT`, or the one
     above;
   - connects to ClickHouse as `CLICKHOUSE_USER` (default `default`) with
     `CLICKHOUSE_PASSWORD`;
   - needs `certifi` (uv installs it): python.org's Python on macOS does
     not see the system's root certificates.

   Coverage:

   - A sensor without a file for a day has no readings that day; some
     sensors the API lists have no file at all.
   - A sensor silent since before the first snapshot is not loaded, so
     a year back holds fewer sensors than the archive. The
     archive's own count per country and day
     (`sensors_per_country_per_day.json` at its root) runs higher,
     without saying which sensors it includes.
   - Only SDS011, PMS5003, BME280 and DHT22 sensors load: the package
     reads no other type.
   - Values load as the files have them. Where firmware sends pressure
     in hPa instead of Pa (a BME280 in Australia), the package reads 300
     to 1,100 as hPa and converts it (`input.sql`).

   <details><summary>load_sensor_community.py</summary>

   ```python
   import concurrent.futures, csv, datetime, gzip, http.client, io, os, ssl, sys, time, urllib.error, urllib.parse, urllib.request
   import certifi

   url, db, country, since, until = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
   AGENT = os.environ.get("SENSOR_COMMUNITY_AGENT", "dactopus-data-models loader (https://github.com/Dactopus)")
   ARCHIVE = "https://archive.sensor.community"
   TLS = ssl.create_default_context(cafile=certifi.where())
   LOGIN = {"X-ClickHouse-User": os.environ.get("CLICKHOUSE_USER", "default"),
            "X-ClickHouse-Key": os.environ.get("CLICKHOUSE_PASSWORD", "")}
   NOW = datetime.datetime.now(datetime.timezone.utc)
   THIS_YEAR = str(NOW.year)
   PUBLISHED = (NOW - datetime.timedelta(hours=10)).date() - datetime.timedelta(days=1)
   TYPES = {"SDS011": "sds011", "PMS5003": "pms5003", "BME280": "bme280", "DHT22": "dht22"}
   COLUMNS = ["sensor_id", "sensor_type", "location", "lat", "lon", "timestamp",
              "P1", "P2", "temperature", "humidity", "pressure"]


   def query(sql, body=None, **settings):
       req = urllib.request.Request(url + "/?" + urllib.parse.urlencode({"query": sql, **settings}), body, LOGIN)
       try:
           return urllib.request.urlopen(req, context=TLS).read().decode()
       except urllib.error.HTTPError as e:
           sys.exit(e.read().decode())


   def get(path):
       """The file's bytes, None when the archive has no such file."""
       for attempt in range(5):
           try:
               with urllib.request.urlopen(urllib.request.Request(path, headers={"User-Agent": AGENT}), context=TLS, timeout=60) as r:
                   return r.read()
           except urllib.error.HTTPError as e:
               if e.code == 404:
                   return None
               if e.code < 500 and e.code != 429:
                   raise
           except (OSError, http.client.HTTPException):  # timeouts and resets, while reading too
               pass
           time.sleep(2 ** attempt)  # the archive drops a connection now and then
       sys.exit(f"gave up on {path}")


   def fetch(day, kind, sensor, indoor):
       # A moved sensor may have either suffix; the flagged one goes first.
       for suffix in (("_indoor", "") if indoor else ("", "_indoor")):
           name = f"{day}_{kind}_sensor_{sensor}{suffix}.csv"
           paths = (f"{ARCHIVE}/{day}/{name}", f"{ARCHIVE}/{day[:4]}/{day}/{name}.gz")
           # Earlier years are in their year's folder; the current one's
           # files are in the root until the archive moves them.
           for path in (paths if day[:4] == THIS_YEAR else paths[::-1]):
               data = get(path)
               if data is not None:
                   return gzip.decompress(data) if path.endswith(".gz") else data
       return None


   sensors = [(TYPES[t], s, i == "true") for s, t, i in csv.reader(io.StringIO(query(
       f"SELECT sensor_id, sensor_type, argMax(indoor, snapshot_at) FROM {db}.locations WHERE country = {{country:String}} "
       f"AND sensor_type IN ({', '.join(repr(t) for t in TYPES)}) GROUP BY sensor_id, sensor_type FORMAT CSV",
       param_country=country)))]
   if not sensors:
       sys.exit(f"no sensors of {country} in {db}.locations: take a snapshot first")
   if not since:
       sys.exit(f"no readings of {country} in {db}.readings: load the history first")
   pool = concurrent.futures.ThreadPoolExecutor(4)
   day, last = datetime.date.fromisoformat(since), datetime.date.fromisoformat(until)
   if last > PUBLISHED:
       print(f"the archive may still be publishing the days after {PUBLISHED}: loading to {PUBLISHED}", flush=True)
       last = PUBLISHED
   while day <= last:
       out = io.StringIO()
       writer = csv.DictWriter(out, COLUMNS, delimiter=";", extrasaction="ignore", restval="")
       writer.writeheader()
       files = 0
       for data in pool.map(lambda ks: fetch(day.isoformat(), *ks), sensors):
           if data:
               files += 1
               writer.writerows(csv.DictReader(io.StringIO(data.decode()), delimiter=";"))
       if files:
           # Some firmware writes the word unknown for a measure it could not
           # take; it becomes NULL.
           query(f"INSERT INTO {db}.readings FORMAT CSVWithNames", out.getvalue().encode(),
                 format_csv_delimiter=";", input_format_csv_use_default_on_bad_values=1)
       print(day, files, "files of", len(sensors), "sensors", flush=True)
       day += datetime.timedelta(days=1)
   ```

   </details>

4. **Build** `readings`, `devices_archive` and the view `devices` into
   the target database (`CLICKHOUSE_DATABASE`, default `dactopus`).
   Times and dates are UTC, with no time zone to set.

   ```bash
   dbt build --project-dir sources/sensor_community
   ```

5. **Validate and check.** Validate the model against the built tables,
   then compare `check_numbers.py`'s answers to 17 questions over the
   hand-written rows of
   [`tests/sensor_community/fixture.sql`](../../tests/sensor_community/fixture.sql)
   with numbers worked out by hand.

   ```bash
   dactopus-ossie-clickhouse validate entities/iot.yaml --url http://user:password@host:8123/dactopus
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < sources/sensor_community/input.sql
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < tests/sensor_community/fixture.sql
   CLICKHOUSE_DATABASE=sensor_community_sample dbt build --project-dir sources/sensor_community \
       --vars '{sensor_community_input_database: sensor_community_sample_raw}'
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/sensor_community_sample python3 tests/sensor_community/check_numbers.py
   ```

6. **Ask.** Serve `entities/iot.yaml` with `dactopus-ossie-clickhouse serve`
   at the database of step 4. Try each site's average temperature over
   the last week, devices silent for over an hour, PM2.5 by day, and how
   many devices reported yesterday. How the model
   measures silence: [docs/iot.md](../../docs/iot.md#limits).

7. **Next loads.** Daily after 10:00 UTC, load from the day after the
   country's last loaded day to yesterday, keep the snapshots running
   and build again. `devices_archive`, one row per site, is rebuilt
   whole from every reading, so its time grows with the history: 0.05 seconds on a laptop for a month of Australia, 2.3
   million readings. Loading a day twice by hand is harmless: the
   package reads each reading once.

   ```bash
   since=$(clickhouse client --query "SELECT max(toDate(timestamp)) + 1 FROM sensor_community_raw.readings
       WHERE sensor_id IN (SELECT sensor_id FROM sensor_community_raw.locations WHERE country = 'AU') HAVING count() > 0")
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU "$since" "$(date -u -v-1d +%F)"
   ```

   On Linux, yesterday is `$(date -u -d yesterday +%F)`.

## Variables

| Variable | Default | What it sets | Guarded |
| --- | --- | --- | --- |
| `sensor_community_input_database` | `sensor_community_raw` | the database of the input tables | no |
| `sensor_community_source_id` | `sensor_community` | the network's label in every row (`source_id`, [labels](../../docs/deployment.md#labels)) | yes |
| `sensor_community_lookback_days` | `3` | the days an incremental run rereads before the latest data it has seen | no |

## Changing a setting

`readings` is incremental: a run rebuilds the sensor-days loaded
recently ([`sensor_community_lookback_days`](#variables)). A change of a
guarded variable needs `dbt build --full-refresh` once
([docs/deployment.md](../../docs/deployment.md#changing-a-setting)); a
run that stops on one does not build `devices_archive`, which reads
`readings`. The dbt user needs `ALTER MODIFY COMMENT` (part of
`ALTER TABLE`) on `readings`.
