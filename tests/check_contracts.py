# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Check the packages' column contracts against the Ossie models and each other.

Every package enforces a dbt contract on every model (dbt_project.yml,
`+contract: {enforced: true}`): models/schema.yml lists each column of the
table or view the model writes, with its ClickHouse type, and a build stops
on a column or a type the list does not have. The columns an Ossie model
reads (fields, metrics, keys and relationships) are the canonical columns
of its datasets. A package that serves the model (deployment.yml, `model`)
lists them first in each dataset's table, in the order the model first
reads them, and with the types every other package that serves the model
gives them: the tables of two packages then add up with UNION ALL. The
columns after them are the package's own.

Run from the repository root:

    uv run tests/check_contracts.py

Checks every package under sources/: contracts are enforced; every model
has a contract with a type for each column; each dataset of the package's
Ossie model is a model of the package whose contract starts with the
dataset's canonical columns; the packages that serve one Ossie model give
each canonical column one type. With --built <package>, also checks the
tables and views of that package in $CLICKHOUSE_DATABASE against its
contracts, column by column in order: dbt checks the types of a view but
keeps the order of its SELECT.

Connection, for --built: CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP),
CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, CLICKHOUSE_DATABASE (default
dactopus), as for the packages.
"""
import argparse
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

import sqlglot
import yaml
from sqlglot import exp

ROOT = pathlib.Path(__file__).resolve().parent.parent


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
    # TSV escapes a quote: DateTime(\'UTC\') is DateTime('UTC').
    return [[value.replace("\\'", "'") for value in line.split("\t")] for line in response.splitlines()]


def references(expression):
    """The columns an ANSI_SQL expression names, in order: (dataset or None, column).

    Read as Snowflake, which takes DATEDIFF(MINUTE, a, b) as the executor
    does: SQLGlot's default reads the unit as a column and b as the unit.
    """
    found = []
    for column in sqlglot.parse_one(expression, read="snowflake").find_all(exp.Column):
        reference = (column.table or None, column.name)
        if reference not in found:
            found.append(reference)
    return found


def expression(item):
    return next(d["expression"] for d in item["expression"]["dialects"] if d["dialect"] == "ANSI_SQL")


def canonical_columns(model_path):
    """{dataset source: [column, ...]}: the columns the Ossie model reads, in the order it first reads them.

    A name that is one of the dataset's fields stands for the columns of
    that field's expression; any other name is a column.
    """
    model = yaml.safe_load(model_path.read_text())
    datasets = {d["name"]: d for d in model["datasets"]}
    fields = {name: {f["name"]: [c for _, c in references(expression(f))] for f in d.get("fields", [])}
              for name, d in datasets.items()}
    read = {name: [] for name in datasets}

    def add(dataset, name):
        for column in fields[dataset].get(name, [name]):
            if column not in read[dataset]:
                read[dataset].append(column)

    for name, dataset in datasets.items():
        for item in dataset.get("fields", []) + dataset.get("metrics", []):
            for _, column in references(expression(item)):
                add(name, column)
        for column in dataset.get("primary_key") or []:
            add(name, column)
    for relationship in model.get("relationships", []):
        for side in ("from", "to"):
            for column in relationship[f"{side}_columns"]:
                add(relationship[side], column)
    for metric in model.get("metrics", []):
        for dataset, column in references(expression(metric)):
            add(dataset, column)
    return {datasets[name]["source"]: columns for name, columns in read.items()}


def contracts(package):
    """{model: [(column, type), ...]} from the package's schema.yml, in the order listed."""
    schema = yaml.safe_load((package / "models" / "schema.yml").read_text())
    return {m["name"]: [(c["name"], c.get("data_type")) for c in m.get("columns", [])] for m in schema["models"]}


def normal(data_type):
    return "".join(str(data_type).split())


def check(packages, built):
    problems = []
    served = {}
    for package in packages:
        name = package.name
        project = yaml.safe_load((package / "dbt_project.yml").read_text())
        config = project["models"][project["name"]]
        if config.get("+contract") != {"enforced": True}:
            problems.append(f"{name}: dbt_project.yml must set +contract: {{enforced: true}} for all models")
        declared = contracts(package)
        models = sorted(p.stem for p in (package / "models").glob("*.sql"))
        for model in models:
            if model not in declared:
                problems.append(f"{name}: model {model} has no columns in schema.yml")
            elif not declared[model] or any(t is None for _, t in declared[model]):
                problems.append(f"{name}: every column of {model} needs a data_type in schema.yml")
        model_file = yaml.safe_load((package / "deployment.yml").read_text())["model"]
        for table, columns in canonical_columns(ROOT / model_file).items():
            if table not in declared:
                problems.append(f"{name}: {model_file} reads {table}, which is not a model of the package")
                continue
            listed = [c for c, _ in declared[table]]
            if listed[:len(columns)] != columns:
                problems.append(f"{name}: {table} must start with the columns {model_file} reads, in this order: "
                                f"{', '.join(columns)}; it starts with {', '.join(listed[:len(columns)])}")
            types = dict(declared[table])
            for column in columns:
                served.setdefault((model_file, table, column), {})[name] = types.get(column)
        if name == built:
            database = os.environ.get("CLICKHOUSE_DATABASE", "dactopus")
            for model in models:
                actual = clickhouse("SELECT name, type FROM system.columns WHERE database = {db:String} "
                                    "AND table = {t:String} ORDER BY position", db=database, t=model)
                expected = declared.get(model, [])
                if [(c, normal(t)) for c, t in actual] != [(c, normal(t)) for c, t in expected]:
                    problems.append(f"{name}: {database}.{model} has the columns "
                                    f"{', '.join(f'{c} {t}' for c, t in actual)}; its contract lists "
                                    f"{', '.join(f'{c} {t}' for c, t in expected)}")
    for (model_file, table, column), types in sorted(served.items()):
        if len({normal(t) for t in types.values()}) > 1:
            problems.append(f"{model_file}: {table}.{column} has different types: "
                            f"{', '.join(f'{p} {t}' for p, t in sorted(types.items()))}")
    return problems


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--built", metavar="PACKAGE", type=pathlib.Path,
                    help="a package's directory, sources/<source>, built into $CLICKHOUSE_DATABASE")
args = parser.parse_args()
packages = sorted(p for p in (ROOT / "sources").iterdir() if (p / "dbt_project.yml").is_file())
if args.built and args.built.name not in {p.name for p in packages}:
    sys.exit(f"{args.built} is not a package under sources/")
failed = check(packages, args.built.name if args.built else None)
for problem in failed:
    print(f"FAIL {problem}")
if not failed:
    print(f"contracts agree: {', '.join(p.name for p in packages)}")
sys.exit(1 if failed else 0)
