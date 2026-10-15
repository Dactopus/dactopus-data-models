"""Compare the age `dbt source freshness` reported with ClickHouse's own.

A freshness macro can return a time the driver reads in the wrong time
zone, and the age is then off by hours while the source still passes.
Run after `dbt source freshness`, with the project's directory and a query
for the latest load time of its one source with freshness, e.g.:

    python3 tests/check_freshness.py sources/shopify \
        "SELECT max(loaded_at) FROM shopify_input.orders"

Connection: CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER,
CLICKHOUSE_PASSWORD, as for the packages.
"""
import json
import os
import pathlib
import sys
import urllib.request
from datetime import datetime, timezone


def clickhouse(query):
    url = f"http://{os.environ.get('CLICKHOUSE_HOST', 'localhost')}:{os.environ.get('CLICKHOUSE_PORT', '8123')}/"
    request = urllib.request.Request(url, query.encode(), headers={
        "X-ClickHouse-User": os.environ.get("CLICKHOUSE_USER", "default"),
        "X-ClickHouse-Key": os.environ.get("CLICKHOUSE_PASSWORD", "")})
    return urllib.request.urlopen(request).read().decode().split()


def instant(micros):
    return datetime.fromtimestamp(int(micros) / 1e6, timezone.utc)


project, latest = sys.argv[1], sys.argv[2]
results = json.loads((pathlib.Path(project) / "target" / "sources.json").read_text())["results"]
if len(results) != 1:
    sys.exit(f"expected one source with freshness, got {len(results)}")
result = results[0]
reported = datetime.fromisoformat(result["max_loaded_at"])
snapshotted = datetime.fromisoformat(result["snapshotted_at"])
age = result["max_loaded_at_time_ago_in_s"]
# Unix microseconds do not depend on any time zone.
loaded, now = clickhouse(f"SELECT toUnixTimestamp64Micro(toDateTime64(({latest}), 6)), "
                         "toUnixTimestamp64Micro(now64(6))")
loaded, now = instant(loaded), instant(now)
print(f"{result['unique_id']}: dbt reports {reported} ({age:.0f} s ago at {snapshotted}),"
      f" ClickHouse has {loaded} (now {now})")
failed = [problem for problem, wrong in [
    ("latest load time differs", abs((reported - loaded).total_seconds()) > 0.001),
    ("snapshot time is not within the last 10 minutes",
     not 0 <= (now - snapshotted).total_seconds() <= 600),
    ("age differs from snapshot minus latest load",
     abs(age - (snapshotted - reported).total_seconds()) > 1),
] if wrong]
for problem in failed:
    print(f"FAIL {problem}")
sys.exit(1 if failed else 0)
