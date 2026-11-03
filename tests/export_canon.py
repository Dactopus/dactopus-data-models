# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Write the canonical tables of a built package to CSV files, and the domain's DDL.

The canonical tables are the columns an Ossie model reads (tests/canon.py). A
person without our chain loads these files with tests/<domain>/tables.sql
and asks the model's questions (tests/<package>/questions.yaml) of them:
tests/run_canon.py does it. Run from the repository root after building a
package as tests/<package>/check_numbers.py describes:

    uv run tests/export_canon.py shopify             # tests/shopify/canon/<table>.csv
    uv run tests/export_canon.py shopify --windows   # tests/shopify/canon_windows/<table>.csv

reads the tables of $CLICKHOUSE_DATABASE (connection: CLICKHOUSE_HOST, CLICKHOUSE_PORT
(HTTP), CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, as for the packages) and writes
tests/commerce/tables.sql. A CSV has a header, rows in the order of their columns, a
decimal without trailing zeros, a time in UTC with its offset (2026-09-01
02:00:00+00:00), a flag as true or false and a NULL as \\N. The package's label
source_id is written as the package's name, whatever label the build gave.

With --check it writes nothing and exits with 1 if a file in the repository
differs from the export: CI builds the fixture and runs it, so a change to a
package or a fixture that changes a canonical row shows up as a change to these
files in the same pull request.
"""
import argparse
import csv
import decimal
import io
import json
import os
import urllib.error
import urllib.parse
import urllib.request

import canon
import check_contracts


def rows(database, table, columns):
    """The rows of the table, every column ordered, as dictionaries of JSON values."""
    query = (f"SELECT {', '.join(f'`{c}`' for c in columns)} FROM `{database}`.`{table}` "
             f"ORDER BY {', '.join(f'`{c}`' for c in columns)} FORMAT JSONEachRow")
    settings = urllib.parse.urlencode({"output_format_json_quote_decimals": 1,
                                       "output_format_json_quote_64bit_integers": 1})
    url = (f"http://{os.environ.get('CLICKHOUSE_HOST', 'localhost')}:"
           f"{os.environ.get('CLICKHOUSE_PORT', '8123')}/?{settings}")
    request = urllib.request.Request(url, query.encode(), headers={
        "X-ClickHouse-User": os.environ.get("CLICKHOUSE_USER", "default"),
        "X-ClickHouse-Key": os.environ.get("CLICKHOUSE_PASSWORD", "")})
    try:
        response = urllib.request.urlopen(request).read().decode()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"ClickHouse rejected the query: {error.read().decode().strip()}")
    return [json.loads(line) for line in response.splitlines()]


def cell(value, sql_type):
    if value is None:
        return canon.NULL
    if sql_type == "BOOLEAN":
        return "true" if value in (True, 1, "1", "true") else "false"
    if sql_type.startswith("DECIMAL"):
        return format(decimal.Decimal(value).normalize(), "f")
    if sql_type == "TIMESTAMP WITH TIME ZONE":
        return f"{value}+00:00"
    return str(value)


def render(package, windows):
    """{path: text} of the CSV files of the package's canonical tables and the domain's tables.sql."""
    database = os.environ.get("CLICKHOUSE_DATABASE", "dactopus")
    tables, model_file = canon.canon_tables(package)
    target = canon.csv_dir(package, windows)
    files = {canon.ROOT / "tests" / canon.domain(model_file) / "tables.sql": canon.ddl(tables)}
    for table, columns in tables.items():
        types = [canon.standard_type(t)[0] for _, t in columns]
        found = rows(database, table, [c for c, _ in columns])
        out = io.StringIO()
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow([c for c, _ in columns])
        for row in found:
            writer.writerow([package if c == "source_id" else cell(row[c], t)
                             for (c, _), t in zip(columns, types)])
        files[target / f"{table}.csv"] = out.getvalue()
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package", help="a package under sources/ that serves a commerce model")
    parser.add_argument("--windows", action="store_true",
                        help="the database holds fixture.sql and windows.sql: canon_windows/")
    parser.add_argument("--check", action="store_true",
                        help="write nothing; exit with 1 if a file differs from the export, or is missing or extra")
    args = parser.parse_args()
    files = render(args.package, args.windows)
    if args.check:
        directory = canon.csv_dir(args.package, args.windows)
        extra = {p for p in directory.glob("*.csv")} - set(files) if directory.is_dir() else set()
        problems = [f"{path.relative_to(canon.ROOT)} is not in the export" for path in sorted(extra)]
        problems += [f"{path.relative_to(canon.ROOT)} differs from the export" if path.is_file()
                     else f"{path.relative_to(canon.ROOT)} is missing"
                     for path, text in files.items() if not path.is_file() or path.read_text() != text]
        for problem in problems:
            print(f"FAIL {problem}")
        print(f"{len(files) - len(problems)} of {len(files)} files match the export" if problems
              else f"{len(files)} files match the export")
        raise SystemExit(1 if problems else 0)
    for path, text in files.items():
        path.parent.mkdir(exist_ok=True)
        path.write_text(text)
        print(f"{path.relative_to(canon.ROOT)}: {text.count(chr(10))} lines")


if __name__ == "__main__":
    main()
