# /// script
# dependencies = ["pyyaml", "sqlglot"]
# ///
"""Check a package's settings guard (macros/settings.sql) by running its build.

The guarded variables (meta.guarded_vars in the package's dbt_project.yml)
are the ones the rows already built depend on. A table an incremental
model built records their values in its comment; a run with another value
of one must stop before it reads or deletes a row, with the message
deployments read ("<table> was not built with the settings of this run
(<variable> was <old>, is <new>): run dbt build --full-refresh once"), and
a full refresh must build with the new values and record them.

Run from the repository root, with the package's build command after --,
its variables in --vars as JSON, and for every guarded variable another
value, as JSON:

    CLICKHOUSE_DATABASE=analytics_settings uv run tests/check_settings.py sources/shopify \\
        --change shopify_timezone='"UTC"' --change shopify_source_id='"store_la"' \\
        -- dbt build --project-dir sources/shopify --profiles-dir tests --vars '{...}'

--stop-only takes a value the input cannot be built with (a currency it
has no rate for): the run must stop on it, and the full refresh leaves it
out. The build goes into $CLICKHOUSE_DATABASE, which must not exist: the
check leaves it built with the changed values, and a second check there
stops on its first build.
The check, in order:

1. The build, and the build again with the same values, pass.
2. A run with one guarded variable changed stops, naming that variable
   and no other, for each variable; the incremental tables are unchanged
   after these runs (a checksum of each).
3. A record without a variable reads it as its default: the run passes
   for a variable this build gives its default and stops for one it
   gives another value.
4. A full refresh with every changed value passes and records them; an
   incremental run with them passes, and one with the first values stops.

Connection, for the checksums and the comments: CLICKHOUSE_HOST,
CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, as for the
packages.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

import yaml

from check_contracts import clickhouse, incremental_models

PHRASE = "was not built with the settings of this run"


def build(command, values, *extra):
    """Run the build with these variables; return (passed, output)."""
    words = list(command)
    words[words.index("--vars") + 1] = json.dumps(values, separators=(",", ":"))
    result = subprocess.run(words + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return result.returncode == 0, result.stdout


def passes(command, values, what, *extra):
    passed, output = build(command, values, *extra)
    if not passed:
        sys.exit(f"{output}\nFAIL {what}: the build failed")
    print(f"ok   {what}")


def stops(command, values, variable, what, alone=True):
    """The run stops with the guard's message, naming the variable, and with alone no other."""
    passed, output = build(command, values)
    if passed:
        sys.exit(f"{output}\nFAIL {what}: the build passed")
    others = "" if alone else r"(?:[^()]*; )?"
    tail = r"\): run dbt build --full-refresh once" if alone else r"[;)]"
    if not re.search(rf"{PHRASE} \({others}{re.escape(variable)} was [^;)]*{tail}", output):
        sys.exit(f"{output}\nFAIL {what}: the build failed, but not with \"{PHRASE} ({variable} was ...)\"")
    print(f"ok   {what}")


def same(value, other):
    """Whether two values are the same setting, as the guard compares them (dactopus_setting_value)."""
    def form(v):
        if isinstance(v, dict):
            return {str(k): str(x) for k, x in v.items()}
        if isinstance(v, list):
            return sorted(str(x) for x in v)
        return str(v)
    return form(value) == form(other)


def records(database, tables, values):
    """Each table records these values, as the guard compares them; exits otherwise."""
    for table in tables:
        found = record(database, table) or {}
        if sorted(found) != sorted(values) or not all(same(found[k], v) for k, v in values.items()):
            sys.exit(f"FAIL {database}.{table} records {found}, not {values}")
    print(f"ok   {', '.join(tables)} record {json.dumps(values, sort_keys=True)}")


def checksums(database, tables):
    return [clickhouse(f"SELECT count(), groupBitXor(cityHash64(toString(tuple(*)))) FROM {database}.{table}")
            for table in tables]


def comment(database, table):
    return clickhouse("SELECT comment FROM system.tables WHERE database = {db:String} AND name = {t:String}",
                      db=database, t=table)[0][0]


def record(database, table):
    """The values the table records: the JSON after "built with "."""
    match = re.search(r"(?:^|; )built with (.*)$", comment(database, table))
    return json.loads(match.group(1)) if match else None


def set_record(database, table, values):
    """Write the record, keeping the comment's segments before it."""
    kept = re.sub(r"(?:^|; )built with .*$", "", comment(database, table))
    text = (kept + "; " if kept else "") + "built with " + json.dumps(values, sort_keys=True)
    text = text.replace("\\", "\\\\").replace("'", "\\'")
    clickhouse(f"ALTER TABLE {database}.{table} MODIFY COMMENT '{text}'", statement=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package", type=pathlib.Path, help="the package's directory, sources/<source>")
    parser.add_argument("--change", action="append", default=[], metavar="VARIABLE=JSON",
                        help="another value of a guarded variable")
    parser.add_argument("--stop-only", action="append", default=[], metavar="VARIABLE=JSON",
                        help="another value the input cannot be built with: stopped on, left out of the full refresh")
    if "--" not in sys.argv:
        sys.exit("give the build command after --")
    split = sys.argv.index("--")
    args, command = parser.parse_args(sys.argv[1:split]), sys.argv[split + 1:]
    if "--vars" not in command:
        sys.exit("the build command must give the variables in --vars")
    package = args.package.resolve()
    project = yaml.safe_load((package / "dbt_project.yml").read_text())
    guarded = (project["models"][project["name"]].get("+meta") or {}).get("guarded_vars") or {}
    roles = yaml.safe_load((package / "deployment.yml").read_text()).get("vars") or {}
    changes = {name: json.loads(value) for name, value in (c.split("=", 1) for c in args.change)}
    stop_only = {name: json.loads(value) for name, value in (c.split("=", 1) for c in args.stop_only)}
    if sorted([*changes, *stop_only]) != sorted(guarded):
        sys.exit(f"give another value of each guarded variable and no other: {', '.join(sorted(guarded))}")
    for role in ("time_zone", "source_id"):
        if role in roles and roles[role] not in changes:
            sys.exit(f"the variable of the {role} role, {roles[role]}, must be changed with --change")
    tables = incremental_models(package)
    if not tables:
        sys.exit(f"{args.package} has no incremental model")
    database = os.environ.get("CLICKHOUSE_DATABASE", "dactopus")
    if clickhouse("EXISTS DATABASE {db:Identifier}", db=database)[0][0] != "0":
        sys.exit(f"the database {database} exists: the check builds into a new one; drop it or set CLICKHOUSE_DATABASE")
    first = json.loads(command[command.index("--vars") + 1])
    values = {name: first.get(name, default) for name, default in guarded.items()}

    passes(command, first, "the build")
    passes(command, first, "the build again, with the same values")
    records(database, tables, values)

    before = checksums(database, tables)
    for name, value in {**changes, **stop_only}.items():
        stops(command, {**first, name: value}, name, f"a run with {name} {json.dumps(value)} stops")
    if checksums(database, tables) != before:
        sys.exit(f"FAIL the runs that stopped changed {', '.join(tables)}")
    print(f"ok   {', '.join(tables)} unchanged")

    # A record without a variable, in every table: one this build gives its
    # default, one it does not. The record is rewritten after the comment's
    # other segments, which stay.
    kept = {table: record(database, table) for table in tables}
    for default, name in [(True, next((n for n in guarded if same(values[n], guarded[n])), None)),
                          (False, next((n for n in guarded if not same(values[n], guarded[n])), None))]:
        if name is None:
            print(f"skip a record without a variable this build gives {'its' if default else 'another value than its'} "
                  f"default: it gives none")
            continue
        for table in tables:
            set_record(database, table, {k: v for k, v in kept[table].items() if k != name})
        if default:
            passes(command, first, f"a record without {name}, which this build gives its default")
        else:
            stops(command, first, name, f"a record without {name}, which this build gives another value than its default")
        for table in tables:
            set_record(database, table, kept[table])

    changed = {**first, **changes}
    passes(command, changed, "a full refresh with the changed values", "--full-refresh")
    expected = {name: changed.get(name, default) for name, default in guarded.items()}
    records(database, tables, expected)
    passes(command, changed, "an incremental run with the changed values")
    name = next(iter(changes))
    stops(command, first, name, f"a run with the first values stops on {name}", alone=False)


if __name__ == "__main__":
    main()
