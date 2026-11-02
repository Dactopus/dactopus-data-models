# /// script
# dependencies = ["pyyaml"]
# ///
"""Check the deployment.yml of a package or a union against it and its built tables.

deployment.yml declares what a deployment of a package sets and reads:
the Ossie model its tables serve (`model`), the dbt variables that take
the input database, the label every row carries (source_id) and the time
zone (`vars`, a role mapped to the variable's name), the zone of the
days when the package fixes it (`zone`, an IANA name) and the built
tables a deployment counts rows per day in (`daily`: `table`, its Date
column `date`, the column `time` whose day `date` is, and `gap: true`
where a day without rows is a finding). Tools that deploy the packages
read it and never read the package's SQL, so nothing else keeps it
true. Run from the repository root after `dbt build` of the package into
$CLICKHOUSE_DATABASE:

    uv run tests/check_deployment.py sources/shopify --time-zone America/New_York
    uv run tests/check_deployment.py sources/sensor_community

A package's days are in one of three zones, and the file says which:
the value of the variable with the role time_zone (Shopify,
WooCommerce), the zone the package fixes in its model (`zone`:
Sensor.Community, UTC), or the source's own, which the export does not
record and only the deployment knows (GA4: neither key). `zone` and the
role time_zone exclude each other. A union's file has no `zone`.

A union (unions/<domain>/) adds up the tables of several databases, each
with a deployment of a package. Its deployment.yml has `model` and `vars`,
which maps one role, input_databases, to the variable that lists those
databases; rows are counted per day in them, by each package's file:

    uv run tests/check_deployment.py unions/commerce

Checks: the file has these keys, may have `zone`, and has no others;
every variable it names is in the package's dbt_project.yml, and the
label's default is one the package accepts (1 to 64 of a-z, 0-9 and _);
the model file exists; every daily table is a model of the package and a
table in the database, its date column a Date and its time column a
DateTime; `zone` is a name zoneinfo knows and the file has no time_zone
beside it.
With --time-zone, counts in every daily table with a time column the
rows whose date is not the day of their time in that zone, and fails on
any such row when the package has a time_zone variable: the table was
built in another zone, or in two (an incremental run after the variable
changed rebuilds only the rows that changed), and is due a
--full-refresh. A package with `zone` needs no --time-zone: the count
runs in `zone` whether or not the option is given, and fails on any
such row (the model or the file is wrong). A --time-zone that differs
from `zone` fails too. A package with neither (GA4: the property's days)
only prints the counts. For a union: the file has the two keys, its
variable is in the union's dbt_project.yml and its model file exists.

Connection: CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER,
CLICKHOUSE_PASSWORD, CLICKHOUSE_DATABASE (default dactopus), as for the
packages.
"""
import argparse
import os
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zoneinfo

import yaml

ROLES = ("input_database", "source_id", "time_zone")
REQUIRED = {"input_database", "source_id"}
LABEL = re.compile(r"[a-z0-9_]{1,64}")
KEYS = {"model", "vars", "daily"}
OPTIONAL_KEYS = {"zone"}
UNION_KEYS = {"model", "vars"}
UNION_ROLES = {"input_databases"}
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
    union = package.parent.name == "unions"
    keys = UNION_KEYS if union else KEYS
    optional = set() if union else OPTIONAL_KEYS
    if not isinstance(declared, dict) or not keys <= set(declared) <= keys | optional:
        may = f", may have {', '.join(sorted(optional))}," if optional else ""
        return [f"deployment.yml must have the keys {sorted(keys)}{may} and no others"]

    model = root / str(declared["model"])
    if not model.is_file():
        problems.append(f"model {declared['model']} is not a file under {root}")

    variables = declared["vars"]
    if union:
        if not isinstance(variables, dict) or set(variables) != UNION_ROLES:
            return problems + [f"vars must map input_databases, and nothing else, to a variable: {variables}"]
        if variables["input_databases"] not in project.get("vars", {}):
            problems.append(f"vars.input_databases: {variables['input_databases']} is not a variable of "
                            f"{project['name']} (dbt_project.yml)")
        return problems
    if not isinstance(variables, dict) or not REQUIRED <= set(variables) \
            or any(role not in ROLES for role in variables):
        problems.append(f"vars must map input_database and source_id, and may map time_zone, to a variable: {variables}")
        variables = {}
    for role, variable in variables.items():
        if variable not in project.get("vars", {}):
            problems.append(f"vars.{role}: {variable} is not a variable of {project['name']} (dbt_project.yml)")
        elif role == "source_id" and not LABEL.fullmatch(str(project["vars"][variable])):
            problems.append(f"vars.source_id: the default of {variable} is not 1 to 64 of a-z, 0-9 and _")

    zone = declared.get("zone")
    if "zone" in declared:
        if not isinstance(zone, str) or zone not in zoneinfo.available_timezones():
            problems.append(f"zone must be an IANA time zone name (zoneinfo), it is {zone!r}")
            zone = None
        elif "time_zone" in variables:
            problems.append("zone and vars.time_zone exclude each other: a package fixes the zone of its days, "
                            "or takes it from a variable")
            zone = None
        elif time_zone and time_zone != zone:
            problems.append(f"--time-zone {time_zone} does not apply: the package fixes its days in {zone} "
                            f"(zone in deployment.yml); leave it out or give {zone}")
    counted_in = zone or time_zone

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
        if time is not None and typed and counted_in:
            [[rows, other]] = clickhouse(
                "SELECT count(), countIf({d:Identifier} != toDate({t:Identifier}, {zone:String})) "
                "FROM {db:Identifier}.{table:Identifier}",
                db=database, table=table, d=date, t=time, zone=counted_in)
            print(f"{database}.{table}: {other} of {rows} rows have a {date} that is not the day of {time} in {counted_in}")
            if int(other) and zone:
                problems.append(f"{table} has rows whose {date} is not the day of {time} in {zone}, "
                                "the zone the package fixes: the model or deployment.yml is wrong")
            elif int(other) and "time_zone" in variables:
                problems.append(f"{table} was not built in {time_zone}, or not whole: run dbt build --full-refresh")
    return problems


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("package", type=pathlib.Path,
                    help="the package's or the union's directory, sources/<source> or unions/<domain>")
parser.add_argument("--time-zone", help="the zone the package was built in, to count the rows whose date is not the day of their time there; a package with `zone` in deployment.yml needs none")
args = parser.parse_args()
failed = check(args.package, args.time_zone)
for problem in failed:
    print(f"FAIL {problem}")
sys.exit(1 if failed else 0)
