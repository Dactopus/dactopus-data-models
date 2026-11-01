# Sensor.Community package

Maps the readings and the sensor registry of
[Sensor.Community](https://sensor.community/), a citizen network of air
quality sensors, onto the `iot` entities: `devices` and `readings`. `iot`
is the reference domain, built from this one public dataset. What the
model answers and its limits: [docs/iot.md](../../docs/iot.md).
Installing the package in a dbt project and several networks:
[docs/deployment.md](../../docs/deployment.md).

## Quick start

[Sensor.Community](https://sensor.community/) is a citizen network of
air quality sensors: over 17,000 sensors reporting particulate matter,
temperature, humidity and pressure every few minutes, with the sensor
registry and the readings published as open data (Open Data Commons
[DbCL 1.0](https://opendatacommons.org/licenses/dbcl/1-0/), linked from
the site's footer). The package loads one country at a time; the
examples take Australia (`AU`), 36 sites and 66 sensors in October 2026.
You need ClickHouse, dbt, dactopus-ossie-clickhouse and
[uv](https://docs.astral.sh/uv/), as in the README's [Quick start](../../README.md#quick-start).

1. **Load** the package's input tables
   [`sources/sensor_community/input.sql`](input.sql).
   Their database is a parameter; the package reads it from the dbt
   variable `sensor_community_input_database` (default
   `sensor_community_raw`).

   ```bash
   clickhouse client --param_db=sensor_community_raw --multiquery < sources/sensor_community/input.sql
   ```

2. **Snapshot** the sensors of the country. The API returns every
   sensor that reported in the last five minutes, with its site's
   coordinates, country and whether it is indoors; nothing else carries
   the country, so the snapshot is the registry, and a sensor appears in
   it once it has reported during a snapshot. ClickHouse reads the API
   itself. The API asks every client for a `User-Agent` that names a
   contact ([the project's wiki](https://github.com/opendata-stuttgart/meta/wiki/APIs));
   put yours in place of the one below.

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

   Run it every five minutes (cron, or anything that runs a query on a
   schedule): each run appends the snapshot, one row per sensor with its
   latest record (the API gives a sensor several in five minutes), and
   the package reads the latest row of each site. A snapshot is visible
   to the model as soon as it is loaded, with no build: it gives each
   site's last contact (`devices.last_contact_at`), country and indoor
   flag. The table
   keeps only each sensor's latest snapshot once ClickHouse merges it
   (`input.sql`), so it stays as large as the country's sensors; the
   history of the snapshots is not kept. The snapshots are also what
   tells a sensor that has gone quiet from one that never existed. Several countries go in one query
   (`country=AU,NZ`); the whole network is
   `https://data.sensor.community/static/v2/data.json`, 17,500 rows.

3. **Load the history.** The archive publishes one CSV file per sensor
   and day, all of a day at once the night after, done by 10:00 UTC. A
   published file does not change. Save the script below as
   `load_sensor_community.py` and run it with the ClickHouse HTTP URL,
   the input database, the country and the first and last day to load:

   ```bash
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU 2025-10-20 2026-10-19
   ```

   It takes the country's sensors from the snapshots, fetches each
   sensor's file for each day (four at a time; an indoor sensor's file
   has the suffix `_indoor`, earlier years are gzipped), and inserts a
   day at a time: about 20 seconds per day of Australia, two hours for
   a year. It loads a day only from 10:00 UTC of the day after, when
   the archive has published it whole, and stops before a later one. A
   sensor without a file for a day has no readings that day; some
   sensors the API lists have no file at all. A sensor that
   stopped reporting before the first snapshot is not in the snapshots
   and is not loaded, so a year back holds fewer sensors than the
   archive. The archive's own count of sensors per country and day
   (`sensors_per_country_per_day.json` at its root) runs higher, and
   does not say which sensors it includes. Sensors of
   other types than SDS011, PMS5003, BME280 and DHT22 are left out: the
   package does not read them. Values load as the files have them. Some
   firmware sends the pressure in hPa instead of Pa (a BME280 in
   Australia); the package reads a pressure from 300 to 1,100 as hPa and
   converts it to Pa (`input.sql`). The script sends the `User-Agent` from
   `SENSOR_COMMUNITY_AGENT`, or the one shown above; set it to yours.
   It connects to ClickHouse as `CLICKHOUSE_USER` (default `default`)
   with `CLICKHOUSE_PASSWORD`. It needs
   [uv](https://docs.astral.sh/uv/) for the one package it uses,
   `certifi`: Python from python.org on macOS does not see the system's
   root certificates.

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
   # The archive publishes a day the night after, done by 10:00 UTC; the
   # last day it has whole.
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
       # An indoor sensor's file has the suffix _indoor; a sensor that moved
       # may have either, so both names are tried, the flagged one first.
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
   the target database (`CLICKHOUSE_DATABASE`, default `dactopus`), with
   the profile of the README's [Quick start](../../README.md#quick-start). Every time and date is UTC, so there is
   no time zone to set.

   ```bash
   dbt build --project-dir sources/sensor_community
   ```

5. **Validate** the model against the built tables, and **check** the
   package's answers: `check_numbers.py` asks 17 questions over the
   hand-written rows of
   [`tests/sensor_community/fixture.sql`](../../tests/sensor_community/fixture.sql),
   built into databases of their own, and compares the answers with
   numbers worked out by hand from the rows.

   ```bash
   dactopus-ossie-clickhouse validate entities/iot.yaml --url http://user:password@host:8123/dactopus
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < sources/sensor_community/input.sql
   clickhouse client --param_db=sensor_community_sample_raw --multiquery < tests/sensor_community/fixture.sql
   CLICKHOUSE_DATABASE=sensor_community_sample dbt build --project-dir sources/sensor_community \
       --vars '{sensor_community_input_database: sensor_community_sample_raw}'
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/sensor_community_sample python3 tests/sensor_community/check_numbers.py
   ```

6. **Ask.** Serve `entities/iot.yaml` with `dactopus-ossie-clickhouse serve`
   at the database of step 4. Try the average temperature at each site
   over the last week, the devices silent for more than an hour, PM2.5
   by day, and how many devices reported yesterday. The archive
   publishes a day the night after, so the latest reading is hours old;
   the model tells agents to measure silence from the latest contact in
   the data, which the snapshots keep within minutes of now, and to name
   that time and its age.

7. **Next loads.** Once a day after 10:00 UTC, load from the day after
   the country's last day loaded to yesterday, keep the snapshots
   running, and build again. The build is incremental for `readings`;
   `devices_archive`, one row per site, is rebuilt whole and reads every
   reading, so its time grows with the history: 0.05 seconds on a laptop
   for a month of Australia, 2.3 million readings. The snapshots need no
   build. Each day is loaded once.
   Loading a day twice by hand is harmless: the package reads each
   reading once.

   ```bash
   since=$(clickhouse client --query "SELECT max(toDate(timestamp)) + 1 FROM sensor_community_raw.readings
       WHERE sensor_id IN (SELECT sensor_id FROM sensor_community_raw.locations WHERE country = 'AU') HAVING count() > 0")
   uv run --with certifi load_sensor_community.py http://localhost:8123 sensor_community_raw AU "$since" "$(date -u -v-1d +%F)"
   ```

   On Linux, yesterday is `$(date -u -d yesterday +%F)`.
