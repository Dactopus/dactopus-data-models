# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Work out the expected answers of the questions of evals/<domain>.yaml in CI.

    uv run tests/check_evals.py [--prefix ci_]                                  # commerce
    uv run tests/check_evals.py web_analytics --from analytics [--prefix ci_]
    uv run tests/check_evals.py iot --from analytics [--prefix ci_]

Fills the databases of the domain's example deployment (evals/deployment.<domain>.example.yaml)
on the server of CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER and CLICKHOUSE_PASSWORD, runs
evals/reference.py with today inside their data, and fails if a query of a question
fails (a renamed metric or field, or a filter the executor no longer takes) or if no
database fits a question. Drops the databases afterwards. Run from the repository root.

Commerce: the canonical tables of the Shopify and WooCommerce packages, each package
alone, and both as two stores of a union, the WooCommerce store's orders read as EUR,
under labels that name the stores (shop_us, woo_eu) and under labels that do not
(brand_a, brand_b); and the union without the WooCommerce store's orders of one month.

Web analytics and IoT have no canonical tables: --from names the database the package's
CI job built from tests/<source>/fixture.sql. Its tables are copied under one label, and
twice under two labels, which name the sites or networks or not. For web analytics a
copy that lacks the latest day stands for a property whose last export has not
arrived; for IoT the two copies share their device ids, as two networks can.

--prefix goes before each database's name, so that runs on one server do not meet.
--out writes the expected answers; --keep leaves the databases for queries by hand.
"""
import argparse
import csv
import io
import json
import pathlib
import subprocess
import sys
import tempfile

import yaml

import canon
import run_canon

# The day the questions are asked, inside each domain's data: the canonical tables'
# months (August to October 2026), the GA4 fixture's days (March 1 and 2, 2025), the
# Sensor.Community fixture's (October 18 and 19, 2026).
TODAY = {"commerce": "2026-10-10", "web_analytics": "2025-03-03", "iot": "2026-10-20"}

# Commerce: each database's packages and their labels.
LABELS = {"evals_shopify": {"shopify": "shopify"}, "evals_woocommerce": {"woocommerce": "woocommerce"},
          "evals_named": {"shopify": "shop_us", "woocommerce": "woo_eu"},
          "evals_opaque": {"shopify": "brand_a", "woocommerce": "brand_b"},
          "evals_quiet": {"shopify": "shop_us", "woocommerce": "woo_eu"}}
# The package whose orders of the database's quiet_month are left out.
QUIET = {"evals_quiet": "woocommerce"}

# Web analytics and IoT: each database's copies of the built tables, a label each, and
# for web analytics whether the copy lacks the latest day (lag).
COPIES = {
    "web_analytics": {"evals_web": [("property_a", False)], "evals_web_lag": [("property_a", True)],
                      "evals_web_named": [("merch_store", False), ("blog", True)],
                      "evals_web_opaque": [("property_a", False), ("property_b", True)]},
    "iot": {"evals_iot": [("network_a", False)], "evals_iot_named": [("sc_city", False), ("sc_lab", False)],
            "evals_iot_opaque": [("network_a", False), ("network_b", False)]},
}
TABLES = {"web_analytics": {"sessions": "session_date", "purchases": "purchase_date", "events": "event_date"},
          "iot": {"readings": None, "devices": None}}


def read_csv(package, table):
    reader = csv.reader(io.StringIO((canon.csv_dir(package, False) / f"{table}.csv").read_text()))
    return next(reader), list(reader)


def quiet(package, month):
    """The ids of the package's orders of the month and of their lines."""
    header, orders = read_csv(package, "orders")
    order_ids = {r[header.index("order_id")] for r in orders
                 if r[header.index("order_date")].startswith(month[:7])}
    header, lines = read_csv(package, "order_lines")
    line_ids = {r[header.index("line_id")] for r in lines if r[header.index("order_id")] in order_ids}
    return order_ids, line_ids


def rows(package, table, label, left_out=(set(), set())):
    """A canonical table's CSV with the store's label, and its orders in EUR for WooCommerce
    in a union, so that the union holds two currencies; less the orders and lines left out."""
    header, body = read_csv(package, table)
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(header)
    for row in body:
        if ("order_id" in header and row[header.index("order_id")] in left_out[0]
                or "line_id" in header and row[header.index("line_id")] in left_out[1]):
            continue
        row[header.index("source_id")] = label
        if table == "orders" and package == "woocommerce" and label != "woocommerce":
            row[header.index("currency")] = "EUR"
        writer.writerow(row)
    return out.getvalue().encode()


def fill_commerce(engine, database, name):
    engine.create((canon.ROOT / "tests" / "commerce" / "tables.sql").read_text())
    for package, label in LABELS[name].items():
        left_out = quiet(package, database["params"]["quiet_month"]) if QUIET.get(name) == package else (set(), set())
        tables, _ = canon.canon_tables(package)
        for table in tables:
            engine.post(f"INSERT INTO {engine.database}.{table} FORMAT CSVWithNames",
                        rows(package, table, label, left_out), date_time_input_format="best_effort")


def fill_copies(engine, domain, name, source):
    engine.post(f"CREATE DATABASE {engine.database}")
    engine.created = True
    for i, (label, lag) in enumerate(COPIES[domain][name]):
        for table, date in TABLES[domain].items():
            # A property that lags lacks the latest day of sessions, and everything after it.
            where = (f"WHERE {date} < (SELECT max(session_date) FROM {source}.sessions)" if lag else "")
            select = f"SELECT * REPLACE ('{label}' AS source_id) FROM {source}.{table} {where}"
            engine.post(f"CREATE TABLE {engine.database}.{table} ENGINE = MergeTree ORDER BY tuple() AS {select}"
                        if i == 0 else f"INSERT INTO {engine.database}.{table} {select}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("domain", nargs="?", default="commerce", choices=sorted(TODAY))
    parser.add_argument("--from", dest="source", help="web_analytics and iot: the database CI built")
    parser.add_argument("--prefix", default="", help="before each database's name")
    parser.add_argument("--out", help="write the expected answers to this file")
    parser.add_argument("--keep", action="store_true", help="leave the databases on the server")
    args = parser.parse_args()
    if args.domain != "commerce" and not args.source:
        parser.error(f"{args.domain} needs --from, the database CI built")

    root = canon.ROOT
    example = root / "evals" / f"deployment.{args.domain}.example.yaml"
    deployment = yaml.safe_load(example.read_text())
    engines = []
    try:
        for database in deployment["databases"]:
            name = database["name"]
            database["name"] = args.prefix + name
            engine = run_canon.ClickHouse(database["name"], deployment["time_zone"])
            engines.append(engine)
            if args.domain == "commerce":
                fill_commerce(engine, database, name)
            else:
                fill_copies(engine, args.domain, name, args.source)
        deployment["models"] = [str(root / m.removeprefix("../")) for m in deployment["models"]]
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as file:
            yaml.safe_dump(deployment, file, sort_keys=False)
        out = subprocess.run([sys.executable, str(root / "evals" / "reference.py"),
                              str(root / "evals" / f"{args.domain}.yaml"), file.name,
                              "--today", TODAY[args.domain]], capture_output=True, text=True)
        pathlib.Path(file.name).unlink()
        sys.stderr.write(out.stderr)
        entries = json.loads(out.stdout or "[]")
        if args.out:
            pathlib.Path(args.out).write_text(out.stdout)
        empty = [f"{e['id']} over {e['database']}" for e in entries
                 if e["readings"] and not any(r["rows"] for r in e["readings"][0])]
        print(f"{len(entries)} questions and databases worked out, {len(empty)} with no rows: "
              + ", ".join(empty))
        # A question no database fits is never worked out.
        skipped = [line for line in out.stderr.splitlines() if line.startswith("skipped ")]
        sys.exit(out.returncode or bool(skipped))
    finally:
        for engine in engines:
            if not args.keep:
                engine.close()


if __name__ == "__main__":
    main()
