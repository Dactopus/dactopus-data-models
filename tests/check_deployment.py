# /// script
# dependencies = ["pyyaml"]
# ///
"""Check a package's deployment.yml against the package and its built tables.

deployment.yml declares what a deployment of a package sets and reads: the
Ossie model its tables serve (`model`), the dbt variables that take the
input database and the time zone (`vars`, a role mapped to the variable's
name), and the built tables a deployment counts rows per day in (`daily`:
`table`, its Date column `date`, the column `time` whose day `date` is,
and `gap: true` where a day without rows is a finding). Tools that deploy
the packages read it and never read the package's SQL, so nothing else
keeps it true. Run from the repository root after `dbt build` of the
package into $CLICKHOUSE_DATABASE:

    uv run tests/check_deployment.py sources/shopify --time-zone America/New_York

Checks: the file has these keys and no others; every variable it names
is in the package's dbt_project.yml; the model file exists; every daily
table is a model of the package and a table in the database, its date
column a Date and its time column a DateTime. With --time-zone, counts in
every daily table with a time column the rows whose date is not the day
of their time in that zone, and fails on any such row when the package
has a time_zone variable: the table was built in another zone, or in two
(an incremental run after the variable changed rebuilds only the rows
that changed), and is due a --full-refresh. A package without the
variable (GA4: the property's days) only prints the counts.

Connection: CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER,
CLICKHOUSE_PASSWORD, CLICKHOUSE_DATABASE (default dactopus), as for the
packages.
"""
import argparse
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

import yaml

ROLES = ("input_database", "time_zone")
KEYS = {"model", "vars", "daily"}
DAILY_KEYS = {"table", "date", "time", "gap"}


def clickhouse(query, **params):
    """Run a query with {name:Type} parameters; return the rows, each a list of columns."""
    query_string = urllib.parse.urlencode({f"param_{name}": value for name, value in params.items()})
    url = (f"http://{os.environ.get('CLICKHOUSE_HOST', 'localhost')}:"
           f"{os.environ.get('CLICKHOUSE_PORT', '8123')}/?{query_string}")
    request = urllib.request.Request(url, (query + " FORMAT TSV").encode(), headers={
        "X-ClickHouse-User": os.environ.get("CLICKHOUSE_USER", "default"),
        "X-ClickHouse-Key": os.environ.get("CLICKHOUSE_PASSWORD", "")})
    try:
        response = urllib.request.urlopen(request).read().decode()
    except urllib.error.HTTPError as error:
        sys.exit(f"ClickHouse rejected the query: {error.read().decode().strip()}")
    return [line.split("\t") for line in response.splitlines()]


def check(package, time_zone):
    """Return the problems found; an empty list means the file agrees with the package."""
    problems = []
    root = package.parent.parent
    database = os.environ.get("CLICKHOUSE_DATABASE", "dactopus")
    declared = yaml.safe_load((package / "deployment.yml").read_text())
    project = yaml.safe_load((package / "dbt_project.yml").read_text())
    if not isinstance(declared, dict) or set(declared) != KEYS:
        return [f"deployment.yml must have the keys {sorted(KEYS)} and no others"]

    model = root / str(declared["model"])
    if not model.is_file():
        problems.append(f"model {declared['model']} is not a file under {root}")

    variables = declared["vars"]
    if not isinstance(variables, dict) or "input_database" not in variables \
            or any(role not in ROLES for role in variables):
        problems.append(f"vars must map input_database, and may map time_zone, to a variable: {variables}")
        variables = {}
    for role, variable in variables.items():
        if variable not in project.get("vars", {}):
            problems.append(f"vars.{role}: {variable} is not a variable of {project['name']} (dbt_project.yml)")

    daily = declared["daily"]
    if not isinstance(daily, list) or not daily:
        problems.append(f"daily must be a list of tables: {daily}")
        daily = []
    for entry in daily:
        if not isinstance(entry, dict) or not {"table", "date"} <= set(entry) <= DAILY_KEYS \
                or not isinstance(entry.get("gap", False), bool):
            problems.append(f"a daily entry has table, date, optionally time and gap (a boolean): {entry}")
            continue
        table, date, time = entry["table"], entry["date"], entry.get("time")
        if not (package / "models" / f"{table}.sql").is_file():
            problems.append(f"daily table {table} is not a model of the package (models/{table}.sql)")
        columns = dict(clickhouse("SELECT name, type FROM system.columns WHERE database = {db:String} AND table = {t:String}",
                                  db=database, t=table))
        if not columns:
            problems.append(f"daily table {table} is not in the database {database}")
            continue
        typed = True
        if columns.get(date) not in ("Date", "Date32"):
            problems.append(f"{table}.{date} must be a Date column, it is {columns.get(date)}")
            typed = False
        if time is not None and not str(columns.get(time)).startswith("DateTime"):
            problems.append(f"{table}.{time} must be a DateTime column, it is {columns.get(time)}")
            typed = False
        if time is not None and typed and time_zone:
            [[rows, other]] = clickhouse(
                "SELECT count(), countIf({d:Identifier} != toDate({t:Identifier}, {zone:String})) "
                "FROM {db:Identifier}.{table:Identifier}",
                db=database, table=table, d=date, t=time, zone=time_zone)
            print(f"{database}.{table}: {other} of {rows} rows have a {date} that is not the day of {time} in {time_zone}")
            if int(other) and "time_zone" in variables:
                problems.append(f"{table} was not built in {time_zone}, or not whole: run dbt build --full-refresh")
    return problems


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("package", type=pathlib.Path, help="the package's directory, sources/<source>")
parser.add_argument("--time-zone", help="the zone the package was built in, to count the rows whose date is not the day of their time there")
args = parser.parse_args()
failed = check(args.package, args.time_zone)
for problem in failed:
    print(f"FAIL {problem}")
sys.exit(1 if failed else 0)
