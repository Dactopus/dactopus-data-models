# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Check the column contracts of the packages and the unions against the Ossie models and each other.

Every package enforces a dbt contract on every model (dbt_project.yml,
`+contract: {enforced: true}`): models/schema.yml lists each column of the
table or view the model writes, with its ClickHouse type, and a build stops
on a column or a type the list does not have. The columns an Ossie model
reads (fields, metrics, keys and relationships) are the canonical columns
of its datasets. A package that serves the model (deployment.yml, `model`)
lists them first in each dataset's table, in the order the model first
reads them, and with the types every other package that serves the model
gives them: the tables of two packages then add up with UNION ALL. The
columns after them are the package's own. A union (unions/<domain>/) adds
up the tables of several databases, each built by a package: one view per
dataset, with the canonical columns and no others.

Run from the repository root:

    uv run tests/check_contracts.py

Checks every package under sources/: contracts are enforced; every model
has a contract with a type for each column, the first of them the label
source_id, LowCardinality(String), under the package's one-label test
(<package>_one_source_id); each dataset of the package's
Ossie model is a model of the package whose contract starts with the
dataset's canonical columns; the packages that serve one Ossie model give
each canonical column one type; the dataset's primary_key without
source_id is tested unique (unique on its one column, or
<package>_unique_key on its columns). Checks every union under unions/:
its models are views with enforced contracts, one for each dataset of
its Ossie model and no others; each lists exactly the dataset's
canonical columns, with the packages' types; source_id is under the test
that each label is in one database (<domain>_union_distinct_source_ids).
With one label in each database and the packages' key tests, that keeps
every key unique in a union. In every Ossie model under entities/,
source_id comes first in each primary_key and on both sides of each
relationship: without it a union joins rows across instances. The copies
of one macro file are the same: macros/freshness.sql in every package,
macros/union.sql in every union. With --built
<package or union>, also checks its tables and views in
$CLICKHOUSE_DATABASE against its contracts, column by column in order:
dbt checks the types of a view but keeps the order of its SELECT.

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
LABEL_TYPE = "LowCardinality(String)"


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


def column_tests(project):
    """{model: {column: the names of its tests}} from the project's schema.yml."""
    schema = yaml.safe_load((project / "models" / "schema.yml").read_text())
    return {m["name"]: {c["name"]: [t if isinstance(t, str) else next(iter(t)) for t in c.get("data_tests", [])]
                        for c in m.get("columns", [])}
            for m in schema["models"]}


def label_tests(project):
    """{model: the tests on its source_id column} from the project's schema.yml."""
    return {model: columns.get("source_id", []) for model, columns in column_tests(project).items()}


def normal(data_type):
    return "".join(str(data_type).split())


def model_tests(project):
    """{model: {test: its arguments}} for the tests on whole models in the project's schema.yml."""
    schema = yaml.safe_load((project / "models" / "schema.yml").read_text())
    tests = {}
    for m in schema["models"]:
        for test in m.get("data_tests", []):
            name, config = (test, {}) if isinstance(test, str) else next(iter(test.items()))
            tests.setdefault(m["name"], {})[name] = (config or {}).get("arguments", {})
    return tests


def check_built(name, models, declared):
    """Problems of the project's tables and views in $CLICKHOUSE_DATABASE against its contracts."""
    problems = []
    database = os.environ.get("CLICKHOUSE_DATABASE", "dactopus")
    for model in models:
        actual = clickhouse("SELECT name, type FROM system.columns WHERE database = {db:String} "
                            "AND table = {t:String} ORDER BY position", db=database, t=model)
        expected = declared.get(model, [])
        if [(c, normal(t)) for c, t in actual] != [(c, normal(t)) for c, t in expected]:
            problems.append(f"{name}: {database}.{model} has the columns "
                            f"{', '.join(f'{c} {t}' for c, t in actual)}; its contract lists "
                            f"{', '.join(f'{c} {t}' for c, t in expected)}")
    return problems


def typed(name, model, declared):
    """A problem if the model has no contract or a column without a type, else None."""
    if model not in declared:
        return f"{name}: model {model} has no columns in schema.yml"
    if not declared[model] or any(t is None for _, t in declared[model]):
        return f"{name}: every column of {model} needs a data_type in schema.yml"
    return None


def check(packages, unions, built):
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
            problem = typed(name, model, declared)
            if problem:
                problems.append(problem)
            elif declared[model][0] != ("source_id", LABEL_TYPE) \
                    or f"{name}_one_source_id" not in label_tests(package)[model]:
                problems.append(f"{name}: {model} must start with source_id {LABEL_TYPE}, "
                                f"tested by {name}_one_source_id")
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
        # A database holds one label, so the key without it is unique in
        # the package's table: unique on its one column, or
        # <package>_unique_key on its columns.
        unique_columns, tests = column_tests(package), model_tests(package)
        for dataset in yaml.safe_load((ROOT / model_file).read_text())["datasets"]:
            table = dataset["source"]
            key = [c for c in dataset.get("primary_key") or [] if c != "source_id"]
            if not key or table not in declared:
                continue
            if not (len(key) == 1 and "unique" in unique_columns.get(table, {}).get(key[0], [])
                    or tests.get(table, {}).get(f"{name}_unique_key", {}).get("columns") == key):
                problems.append(f"{name}: {table} must test that its key in {model_file} without source_id, "
                                f"{', '.join(key)}, is unique: unique on the column, or {name}_unique_key "
                                f"with the columns")
        if package == built:
            problems += check_built(name, models, declared)
    for union in unions:
        name = f"unions/{union.name}"
        prefix = f"{union.name}_union"
        project = yaml.safe_load((union / "dbt_project.yml").read_text())
        config = project["models"][project["name"]]
        if config.get("+contract") != {"enforced": True} or config.get("+materialized") != "view":
            problems.append(f"{name}: dbt_project.yml must set +materialized: view and "
                            f"+contract: {{enforced: true}} for all models")
        declared = contracts(union)
        models = sorted(p.stem for p in (union / "models").glob("*.sql"))
        model_file = yaml.safe_load((union / "deployment.yml").read_text())["model"]
        canonical = canonical_columns(ROOT / model_file)
        if models != sorted(canonical):
            problems.append(f"{name}: its models must be the datasets of {model_file}, "
                            f"{', '.join(sorted(canonical))}; they are {', '.join(models)}")
        for model in models:
            problem = typed(name, model, declared)
            if problem:
                problems.append(problem)
                continue
            if f"{prefix}_distinct_source_ids" not in label_tests(union)[model]:
                problems.append(f"{name}: source_id of {model} must be tested by {prefix}_distinct_source_ids")
            listed = [c for c, _ in declared[model]]
            if model in canonical and listed != canonical[model]:
                problems.append(f"{name}: {model} must list the columns {model_file} reads and no others, "
                                f"in this order: {', '.join(canonical[model])}; it lists {', '.join(listed)}")
            for column, data_type in declared[model]:
                if (model_file, model, column) in served:
                    served[(model_file, model, column)][name] = data_type
        if union == built:
            problems += check_built(name, models, declared)
    for model_path in sorted((ROOT / "entities").glob("*.yaml")):
        model = yaml.safe_load(model_path.read_text())
        name = f"entities/{model_path.name}"
        for dataset in model["datasets"]:
            key = dataset.get("primary_key")
            if key and key[0] != "source_id":
                problems.append(f"{name}: the primary_key of {dataset['name']} must start with source_id: {key}")
        for relationship in model.get("relationships", []):
            if relationship["from_columns"][0] != "source_id" or relationship["to_columns"][0] != "source_id":
                problems.append(f"{name}: {relationship['name']} must join on source_id first, on both sides")
    for (model_file, table, column), types in sorted(served.items()):
        if len({normal(t) for t in types.values()}) > 1:
            problems.append(f"{model_file}: {table}.{column} has different types: "
                            f"{', '.join(f'{p} {t}' for p, t in sorted(types.items()))}")
    # Copies of one file, kept in each project so that each installs alone.
    for projects, macro in ((packages, "freshness.sql"), (unions, "union.sql")):
        texts = {(p / "macros" / macro).read_bytes() if (p / "macros" / macro).is_file() else None for p in projects}
        if None in texts or len(texts) > 1:
            problems.append(f"macros/{macro} must be the same file in each of "
                            f"{', '.join(str(p.relative_to(ROOT)) for p in projects)}: copy one over the others")
    return problems


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--built", metavar="PROJECT", type=pathlib.Path,
                    help="a package's or a union's directory, sources/<source> or unions/<domain>, "
                         "built into $CLICKHOUSE_DATABASE")
args = parser.parse_args()
projects = {kind: sorted(p for p in (ROOT / kind).iterdir() if (p / "dbt_project.yml").is_file())
            for kind in ("sources", "unions")}
built = args.built.resolve() if args.built else None
if built and built not in projects["sources"] + projects["unions"]:
    sys.exit(f"{args.built} is not a package under sources/ or a union under unions/")
failed = check(projects["sources"], projects["unions"], built)
for problem in failed:
    print(f"FAIL {problem}")
if not failed:
    print(f"contracts agree: {', '.join(p.name for p in projects['sources'])}; "
          f"unions {', '.join(p.name for p in projects['unions'])}")
sys.exit(1 if failed else 0)
