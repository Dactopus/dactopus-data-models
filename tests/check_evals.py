# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Work out the expected answers of evals/commerce.yaml over the canonical tables.

Loads the canonical tables of the Shopify and WooCommerce packages into the databases
of evals/deployment.example.yaml on the server of CLICKHOUSE_HOST, CLICKHOUSE_PORT
(HTTP), CLICKHOUSE_USER and CLICKHOUSE_PASSWORD: each package alone, and both as two
stores of a union, the WooCommerce store's orders read as EUR, under labels that name
the stores (shop_us, woo_eu) and under labels that do not (brand_a, brand_b). Then runs
evals/reference.py with today inside the tables' months, and fails if a query of a
question fails: a renamed metric or field, or a filter the executor no longer takes.
Drops the databases afterwards. Run from the repository root:

    uv run tests/check_evals.py [--prefix ci_]

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

TODAY = "2026-10-10"  # inside the canonical tables' months (August to October 2026)
LABELS = {"evals_shopify": {"shopify": "shopify"}, "evals_woocommerce": {"woocommerce": "woocommerce"},
          "evals_named": {"shopify": "shop_us", "woocommerce": "woo_eu"},
          "evals_opaque": {"shopify": "brand_a", "woocommerce": "brand_b"}}


def rows(package, table, label):
    """A canonical table's CSV with the store's label, and its orders in EUR for WooCommerce
    in a union, so that the union holds two currencies."""
    text = (canon.csv_dir(package, False) / f"{table}.csv").read_text()
    reader = csv.reader(io.StringIO(text))
    header = next(reader)
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(header)
    for row in reader:
        row[header.index("source_id")] = label
        if table == "orders" and package == "woocommerce" and label != "woocommerce":
            row[header.index("currency")] = "EUR"
        writer.writerow(row)
    return out.getvalue().encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--prefix", default="", help="before each database's name")
    parser.add_argument("--out", help="write the expected answers to this file")
    parser.add_argument("--keep", action="store_true", help="leave the databases on the server")
    args = parser.parse_args()

    root = canon.ROOT
    example = root / "evals" / "deployment.example.yaml"
    deployment = yaml.safe_load(example.read_text())
    ddl = (root / "tests" / "commerce" / "tables.sql").read_text()
    engines = []
    try:
        for database in deployment["databases"]:
            database["name"] = args.prefix + database["name"]
            engine = run_canon.ClickHouse(database["name"], deployment["time_zone"])
            engines.append(engine)
            engine.create(ddl)
            for package, label in LABELS[database["name"][len(args.prefix):]].items():
                tables, _ = canon.canon_tables(package)
                for table in tables:
                    engine.post(f"INSERT INTO {engine.database}.{table} FORMAT CSVWithNames",
                                rows(package, table, label), date_time_input_format="best_effort")
        deployment["models"] = [str(root / m.removeprefix("../")) for m in deployment["models"]]
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as file:
            yaml.safe_dump(deployment, file, sort_keys=False)
        out = subprocess.run([sys.executable, str(root / "evals" / "reference.py"), str(root / "evals" / "commerce.yaml"),
                              file.name, "--today", TODAY], capture_output=True, text=True)
        pathlib.Path(file.name).unlink()
        sys.stderr.write(out.stderr)
        entries = json.loads(out.stdout or "[]")
        if args.out:
            pathlib.Path(args.out).write_text(out.stdout)
        empty = [f"{e['id']} over {e['database']}" for e in entries
                 if e["readings"] and not any(r["rows"] for r in e["readings"][0])]
        print(f"{len(entries)} questions and databases worked out, {len(empty)} with no rows: "
              + ", ".join(empty))
        sys.exit(out.returncode)
    finally:
        for engine in engines:
            if not args.keep:
                engine.close()


if __name__ == "__main__":
    main()
