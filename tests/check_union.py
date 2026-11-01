# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Check a union's answers against the answers of the databases it adds up.

A union (unions/<domain>/) is a database of views over several databases,
each built by a package under its own label (source_id). Its answers
through an Ossie model must be the instances' own: each label's numbers
in the union equal what that label's database gives alone, and a total of
counts and sums equals the sum of theirs. A key or a relationship without
the label would join rows across instances and break the first.

    uv run tests/check_union.py entities/commerce.yaml <union url> <instance url>...

A url is the ClickHouse URL with the database, as $OSSIE_CLICKHOUSE_URL;
the model is asked in $OSSIE_CLICKHOUSE_TIME_ZONE. The questions: every
metric of each dataset by that dataset's source_id; every metric of the
model by the source_id of the first dataset it reads; and, per model in
JOINS, metrics by a label and fields of other datasets, through each
relationship of the model. A count or a sum (an expression that is one
COUNT or SUM) is also asked without dimensions, for the total. A metric
of the time now (CURRENT_TIMESTAMP, CURRENT_DATE) is left out: its
answer moves between the questions. A question no database answers with
a row fails.
"""
import json
import math
import pathlib
import subprocess
import sys

import sqlglot
import yaml
from sqlglot import exp

# Metrics by a label and fields of other datasets: (metric, dimensions).
# Together they go through every relationship of each model. A label from
# the other side of a relationship catches a join across instances that
# leaves the dimension's values alone (two instances of one fixture).
JOINS = {
    "commerce": [
        ("sales_events.net_revenue", ["sales_events.source_id", "orders.new_vs_repeat"]),
        ("sales_events.net_revenue", ["sales_events.source_id", "customers.first_order_month"]),
        ("orders.revenue", ["orders.source_id", "customers.first_order_month"]),
        ("refunds_total", ["orders.source_id", "orders.channel"]),
        ("line_revenue", ["orders.source_id", "products.title"]),
        ("category_net_revenue", ["orders.source_id", "line_categories.category"]),
        ("brand_net_revenue", ["orders.source_id", "line_brands.brand"]),
        ("product_categories.product_count", ["products.source_id", "products.status"]),
        ("product_brands.product_count", ["products.source_id", "products.status"]),
    ],
    "web_analytics": [
        ("purchases.purchase_count", ["purchases.source_id", "sessions.source"]),
        ("events.event_count", ["events.source_id", "sessions.medium"]),
    ],
    "iot": [
        ("readings.reading_count", ["readings.source_id", "devices.country_code", "readings.measure"]),
        ("readings.reporting_devices", ["devices.source_id", "devices.is_indoor"]),
    ],
}


def expression(item):
    return next(d["expression"] for d in item["expression"]["dialects"] if d["dialect"] == "ANSI_SQL")


def parse(item):
    return sqlglot.parse_one(expression(item), read="snowflake")


def now(item):
    return any(word in expression(item).upper() for word in ("CURRENT_TIMESTAMP", "CURRENT_DATE", "NOW("))


def additive(item):
    return isinstance(parse(item), (exp.Sum, exp.Count))


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return a is not None and b is not None and math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9)
    return a == b


def same_rows(got, expected):
    return len(got) == len(expected) and all(
        g.keys() == e.keys() and all(same(g[k], e[k]) for k in e) for g, e in zip(got, expected))


def ask(model, url, metrics, dimensions):
    """The answer's rows, sorted by their dimensions, or the executor's error."""
    args = [a for m in metrics for a in ("-m", m)] + [a for d in dimensions for a in ("-d", d)]
    out = subprocess.run(["dactopus-ossie-clickhouse", "query", model, *args, "--json", "--url", url],
                         capture_output=True, text=True)
    if out.returncode:
        return out.stderr.strip()
    rows = json.loads(out.stdout)
    return sorted(rows, key=lambda r: [str(r[k]) for k in r if k not in metrics])


def questions(model_path):
    """(metrics, dimensions, the additive ones among the metrics); every question has a label among its dimensions."""
    model = yaml.safe_load(model_path.read_text())
    datasets = [d["name"] for d in model["datasets"]]
    found = []
    for dataset in model["datasets"]:
        metrics = [m for m in dataset.get("metrics", []) if not now(m)]
        if metrics:
            found.append(([f"{dataset['name']}.{m['name']}" for m in metrics], [f"{dataset['name']}.source_id"],
                          [f"{dataset['name']}.{m['name']}" for m in metrics if additive(m)]))
    first = {}
    for metric in (m for m in model.get("metrics", []) if not now(m)):
        tables = [c.table for c in parse(metric).find_all(exp.Column) if c.table in datasets]
        first.setdefault(tables[0], []).append(metric)
    for dataset, metrics in first.items():
        found.append(([m["name"] for m in metrics], [f"{dataset}.source_id"],
                      [m["name"] for m in metrics if additive(m)]))
    found += [([metric], dimensions, []) for metric, dimensions in JOINS[model_path.stem]]
    return found


def main(model, union, instances):
    failed = asked = 0
    for metrics, dimensions, totals in questions(pathlib.Path(model)):
        asked += 1
        got = ask(model, union, metrics, dimensions)
        parts = [ask(model, url, metrics, dimensions) for url in instances]
        errors = [p for p in [got, *parts] if isinstance(p, str)]
        expected = sorted((r for p in parts if isinstance(p, list) for r in p),
                          key=lambda r: [str(r[k]) for k in r if k not in metrics])
        if errors or not expected or not same_rows(got, expected):
            failed += 1
            print(f"FAIL {' '.join(metrics)} by {', '.join(dimensions)}\n"
                  f"  the instances {errors or expected}\n  the union     {got}")
            continue
        if totals:
            asked += 1
            total = ask(model, union, totals, [])
            summed = [{m: sum(r[m] or 0 for r in expected) for m in totals}]
            if isinstance(total, str) or not same_rows(total, summed):
                failed += 1
                print(f"FAIL {' '.join(totals)} in total\n  the sum   {summed}\n  the union {total}")
    print(f"{asked - failed} of {asked} questions match")
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
