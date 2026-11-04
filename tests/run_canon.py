# /// script
# dependencies = ["duckdb==1.5.6", "pytz", "pyyaml", "sqlglot"]
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
    uv run tests/run_canon.py shopify --engine duckdb

Prints "N of N questions match" and exits with 1 if one differs.

clickhouse: loads the tables into a new database of the server of
CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, asks
through dactopus-ossie-clickhouse and drops the database. --database names it
(default canon_<package>_<random>); it must not exist.

duckdb: loads the tables into DuckDB in memory (--database: a file instead) and asks
through DuckDB's community extension ossie, which it installs. The extension refuses
some questions; they are printed as refused, with its reason, and do not count as a
difference. CI does not run it: the extension is not ours, and with 0.3.0 two questions
of each package differ: it leaves out the rows a many-to-one relationship finds no
match for.

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
        self.created = False  # close() drops only a database this run created

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
        self.created = True
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
        if self.created:
            self.post(f"DROP DATABASE IF EXISTS {self.database}")


class DuckDB:
    """The tables in a DuckDB database in memory; the model is asked through DuckDB's
    community extension ossie (https://duckdb.org/community_extensions/extensions/ossie).

    The extension (0.3.0) does not read the metrics of a dataset (apache/ossie#591), so
    the model is loaded with each of them moved to the model's metrics as
    <dataset>__<metric>: its columns qualified with the dataset, COUNT(*) counted on the
    dataset's key. The answers name them back. It does not read the `sql` form either, so
    every expression is written back as an ANSI_SQL dialect. The extension refuses a
    question it cannot answer with one aggregate per grain or without fan-out (two facts in one
    question, a filter on a dataset that repeats the counted rows, no metric); such a
    question is reported as refused, not as a wrong number. Any other error is one.
    """

    @staticmethod
    def refused(got):
        return isinstance(got, str) and "Invalid Input Error: ossie: " in got

    def __init__(self, database, time_zone):
        import duckdb

        self.connection = duckdb.connect(database or ":memory:")
        self.connection.execute(f"SET TimeZone = '{time_zone}'")
        self.connection.execute("INSTALL ossie FROM community")
        self.connection.execute("LOAD ossie")
        self.model = None

    def create(self, sql):
        self.connection.execute(sql)

    def load(self, table, csv_path):
        # Read as text and cast to the table's types: a time carries its offset.
        self.connection.execute(f"INSERT INTO {table} SELECT * FROM read_csv(?, header = true, "
                                f"nullstr = '{canon.NULL}', all_varchar = true)", [str(csv_path)])

    def load_model(self, model):
        import tempfile

        import sqlglot
        import yaml
        from sqlglot import exp

        document = yaml.safe_load(pathlib.Path(model).read_text())
        self.metrics = {}
        for dataset in document["datasets"]:
            for metric in dataset.pop("metrics", None) or []:
                expression = sqlglot.parse_one(metric["expression"]["sql"])
                for star in list(expression.find_all(exp.Star)):
                    if isinstance(star.parent, exp.Count):
                        star.replace(exp.column(dataset["primary_key"][-1], dataset["name"]))
                for column in expression.find_all(exp.Column):
                    if not column.table:
                        column.set("table", exp.to_identifier(dataset["name"]))
                metric["expression"]["sql"] = expression.sql()
                name = f"{dataset['name']}.{metric['name']}"
                metric["name"] = self.metrics[name] = f"{dataset['name']}__{metric['name']}"
                document.setdefault("metrics", []).append(metric)
        # The extension reads only `dialects`. Remove once it reads `sql`.
        for item in [*(f for d in document["datasets"] for f in d["fields"]),
                     *document.get("metrics", [])]:
            item["expression"] = {"dialects": [{"dialect": "ANSI_SQL",
                                                "expression": item["expression"]["sql"]}]}
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as file:
            yaml.safe_dump(document, file, sort_keys=False)
        self.connection.execute("CALL ossie_load(?)", [file.name])
        pathlib.Path(file.name).unlink()
        self.names = {moved: name for name, moved in self.metrics.items()}
        self.model = model

    def ask(self, model, case):
        import datetime
        import decimal

        import duckdb

        if self.model != model:
            self.load_model(model)

        def term(name):
            return self.metrics.get(name, name)

        def order(item):
            name, _, direction = item.partition(" ")
            return f'"{term(name)}" {direction}'.strip()

        query = "SELECT * FROM ossie_query(?, ?, ?)"
        if case.get("order"):
            query += " ORDER BY " + ", ".join(order(item) for item in case["order"])
        if "limit" in case:
            query += f" LIMIT {int(case['limit'])}"
        try:
            result = self.connection.execute(query, [[term(m) for m in case.get("metrics", [])],
                                                     case.get("dimensions", []), case.get("filters", [])])
        except duckdb.Error as error:
            return str(error).splitlines()[0]

        def value(v):
            # As dactopus-ossie-clickhouse --json writes them. DATE_TRUNC of a date is a
            # timestamp at midnight in DuckDB, a date in ClickHouse: the same day.
            if isinstance(v, decimal.Decimal):
                return float(v)
            if isinstance(v, datetime.datetime) and v.tzinfo is None and v.time() == datetime.time():
                return v.date().isoformat()
            if isinstance(v, (datetime.date, datetime.datetime)):
                return v.isoformat()
            return v

        # A dimension is named by its field, a metric as it was asked.
        columns = [self.names.get(c[0], c[0].split(".")[-1]) for c in result.description]
        return [dict(zip(columns, map(value, row))) for row in result.fetchall()]

    def close(self):
        self.connection.close()


ENGINES = {"clickhouse": ClickHouse, "duckdb": DuckDB}


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
    try:
        engine.create(ddl)
        for table in tables:
            engine.load(table, csv_dir / f"{table}.csv")
        ask_model.check(str(canon.ROOT / model_file), cases, ask=engine.ask,
                        refused=getattr(engine, "refused", None))
    finally:
        engine.close()


if __name__ == "__main__":
    main()
