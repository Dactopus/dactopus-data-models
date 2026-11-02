# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Ask the commerce model its questions over the canonical tables, with no dbt.

Loads tests/<package>/canon/<table>.csv (with --windows, canon_windows/), declared
by tests/commerce/tables.sql, into an engine, asks the questions of
tests/<package>/questions.yaml (with --windows, its window_cases) in the zone of the
package's build, and compares each answer with the expected rows. These are the
canonical tables tests/export_canon.py wrote from a package's build: what a
person needs to check the model's numbers without our chain from the platform's
raw rows to the model. Run from the repository root:

    uv run tests/run_canon.py shopify --engine clickhouse
    uv run tests/run_canon.py woocommerce --windows --engine clickhouse

Prints "N of N questions match" and exits with 1 if one differs.

clickhouse: loads the tables into a new database of the server of
CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, asks
through dactopus-ossie-clickhouse and drops the database. --database names it
(default canon_<package>_<random>); it must not exist.

Another engine is a class with create(sql), load(table, csv_path) and ask(model, case),
and an entry in ENGINES.
"""
import argparse
import os
import pathlib
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid

import ask_model
import canon

CLICKHOUSE_TYPES = {"VARCHAR": "String", "BIGINT": "Int64", "BOOLEAN": "Bool", "DATE": "Date",
                    "TIMESTAMP WITH TIME ZONE": "DateTime('UTC')"}


def clickhouse_ddl(sql):
    """tables.sql as ClickHouse takes it: its own type names, Nullable where a column is not NOT NULL.

    ClickHouse reads BIGINT, BOOLEAN, DATE, DECIMAL and VARCHAR, but not
    TIMESTAMP WITH TIME ZONE, and a column is not Nullable unless it says so.
    """
    def column(match):
        name, sql_type, not_null, comma = match.groups()
        mapped = CLICKHOUSE_TYPES.get(sql_type, sql_type.replace("DECIMAL", "Decimal"))
        return f"    {name} {mapped if not_null else f'Nullable({mapped})'}{comma}"

    sql = re.sub(r"^    (\w+) (.+?)( NOT NULL)?(,?)$", column, sql, flags=re.M)
    return re.sub(r"\n\);", "\n) ENGINE = MergeTree ORDER BY tuple();", sql)


class ClickHouse:
    """The tables in a new database of a ClickHouse server; the model is asked through dactopus-ossie-clickhouse."""

    def __init__(self, database, time_zone):
        self.database = database or f"canon_{uuid.uuid4().hex[:12]}"
        self.host = os.environ.get("CLICKHOUSE_HOST", "localhost")
        self.port = os.environ.get("CLICKHOUSE_PORT", "8123")
        self.user = os.environ.get("CLICKHOUSE_USER", "default")
        self.password = os.environ.get("CLICKHOUSE_PASSWORD", "")
        self.time_zone = time_zone

    def post(self, query, data=b"", **settings):
        url = f"http://{self.host}:{self.port}/?{urllib.parse.urlencode({**settings, 'query': query})}"
        request = urllib.request.Request(url, data, headers={
            "X-ClickHouse-User": self.user, "X-ClickHouse-Key": self.password})
        try:
            urllib.request.urlopen(request).read()
        except urllib.error.HTTPError as error:
            raise SystemExit(f"ClickHouse rejected the query: {error.read().decode().strip()}")

    def create(self, sql):
        self.post(f"CREATE DATABASE {self.database}")
        for statement in clickhouse_ddl(sql).split(";\n"):
            if statement.strip():
                self.post(statement.replace("CREATE TABLE ", f"CREATE TABLE {self.database}.", 1))

    def load(self, table, csv_path):
        # A time carries its offset (2026-09-01 02:00:00+00:00): best_effort reads it.
        self.post(f"INSERT INTO {self.database}.{table} FORMAT CSVWithNames", csv_path.read_bytes(),
                  date_time_input_format="best_effort")

    def ask(self, model, case):
        # The executor reads these from the environment, and asks in the zone of the build.
        os.environ["OSSIE_CLICKHOUSE_URL"] = (f"http://{urllib.parse.quote(self.user, safe='')}:"
                                              f"{urllib.parse.quote(self.password, safe='')}"
                                              f"@{self.host}:{self.port}/{self.database}")
        os.environ["OSSIE_CLICKHOUSE_TIME_ZONE"] = self.time_zone
        return ask_model.ask(model, case)

    def close(self):
        self.post(f"DROP DATABASE IF EXISTS {self.database}")


ENGINES = {"clickhouse": ClickHouse}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package", help="a package under sources/ that serves a commerce model")
    parser.add_argument("--windows", action="store_true", help="the canon_windows tables and the window_cases")
    parser.add_argument("--engine", required=True, choices=sorted(ENGINES))
    parser.add_argument("--database", help="clickhouse: the new database to load the tables into")
    args = parser.parse_args()

    tables, model_file = canon.canon_tables(args.package)
    source = ask_model.load_questions(args.package)
    cases = source["window_cases" if args.windows else "cases"]
    engine = ENGINES[args.engine](args.database, source["time_zone"])
    ddl = (canon.ROOT / "tests" / canon.domain(model_file) / "tables.sql").read_text()
    csv_dir = canon.csv_dir(args.package, args.windows)
    engine.create(ddl)
    try:
        for table in tables:
            engine.load(table, csv_dir / f"{table}.csv")
        ask_model.check(str(canon.ROOT / model_file), cases, ask=engine.ask)
    finally:
        engine.close()


if __name__ == "__main__":
    main()
