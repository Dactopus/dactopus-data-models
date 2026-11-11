# /// script
# dependencies = ["pyyaml"]
# ///
"""Work out the expected answers of the questions in evals/<domain>.yaml over a deployment.

    uv run evals/reference.py evals/commerce.yaml deployment.yaml --today 2026-10-10 > expected.json

deployment.yaml (see evals/deployment.commerce.example.yaml) names the model files, the time zone,
the databases the agent is asked over and the parameters of the questions. A question
is asked over each database that has as many stores as it needs (`stores`) and provides
what it requires (`requires`); a question no database fits is listed as skipped on
stderr. The queries go through `dactopus-ossie-clickhouse query`, which must be on the
PATH; the server is CLICKHOUSE_HOST, CLICKHOUSE_PORT (HTTP), CLICKHOUSE_USER and
CLICKHOUSE_PASSWORD.

--today is the day the agent was asked, in the deployment's zone: every CURRENT_DATE in a
filter becomes that date. Writes a JSON list, one entry per question and database: the
question as asked, the readings (each a list of queries with their rows), the rows that
must not be in the answer, the rubric and what to say when the answer is empty.
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.parse

import yaml


def url(database):
    user = urllib.parse.quote(os.environ.get("CLICKHOUSE_USER", "default"), safe="")
    password = urllib.parse.quote(os.environ.get("CLICKHOUSE_PASSWORD", ""), safe="")
    host = os.environ.get("CLICKHOUSE_HOST", "localhost")
    port = os.environ.get("CLICKHOUSE_PORT", "8123")
    return f"http://{user}:{password}@{host}:{port}/{database}"


def fill(text, params):
    """The text with its {name} and {name:format} parameters filled in."""
    return text.format(**params)


def query(models, database, time_zone, case, today, params):
    """The rows of one query of the model, with CURRENT_DATE the given day."""
    def resolve(value):
        return fill(value, params).replace("CURRENT_DATE", f"DATE '{today}'")

    args = []
    for flag, key in (("-m", "metrics"), ("-d", "dimensions"), ("-f", "filters"), ("-o", "order")):
        for value in case.get(key, []):
            args += [flag, resolve(value)]
    limit = case.get("limit")
    if limit:
        # A few rows past the limit show a tie at its edge.
        args += ["-l", str(limit + 5)]
    # The URL carries the password: through the environment, not the command line.
    out = subprocess.run(["dactopus-ossie-clickhouse", "query", *models, *args, "--json",
                          "--time-zone", time_zone],
                         capture_output=True, text=True, env={**os.environ, "OSSIE_CLICKHOUSE_URL": url(database)})
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    rows = json.loads(out.stdout)
    required = rows
    if limit:
        # The rows within the limit, less those tied with the first row past it: an
        # answer may list any of the tied rows.
        required = rows[:limit]
        if len(rows) > limit:
            edge = case["order"][0].split()[0]
            edge_value = rows[limit].get(edge)
            untied = [row for row in required if row.get(edge) != edge_value]
            if untied:
                required = untied
            else:
                # Every row within the limit ties: any of them may be listed, and the
                # answer states their value.
                return {"query": dict(case), "rows": required, "tied": True}
    return {"query": dict(case), "rows": required}


def fits(question, database, provides):
    return question.get("stores", 1) == database.get("stores", 1) and set(question.get("requires", [])) <= provides


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("questions", help="evals/<domain>.yaml")
    parser.add_argument("deployment", help="the deployment's file, as evals/deployment.commerce.example.yaml")
    parser.add_argument("--today", required=True, type=datetime.date.fromisoformat,
                        help="the day the agent was asked, in the deployment's zone (YYYY-MM-DD)")
    parser.add_argument("--only", nargs="*", help="these question ids only")
    args = parser.parse_args()

    questions = yaml.safe_load(pathlib.Path(args.questions).read_text())["questions"]
    deployment = yaml.safe_load(pathlib.Path(args.deployment).read_text())
    base = pathlib.Path(args.deployment).parent
    models = [str(base / m) for m in deployment["models"]]
    entries, failures = [], 0
    for question in questions:
        if args.only and question["id"] not in args.only:
            continue
        databases = [d for d in deployment["databases"]
                     if fits(question, d, set(d.get("provides", [])))]
        if not databases:
            print(f"skipped {question['id']}: no database with {question.get('stores', 1)} store(s) "
                  f"providing {question.get('requires', [])}", file=sys.stderr)
            continue
        for database in databases:
            params = {**deployment.get("params", {}), **database.get("params", {})}
            params = {k: datetime.date.fromisoformat(v) if isinstance(v, str) and re.fullmatch(r"\d{4}-\d\d-\d\d", v)
                      else v for k, v in params.items()}
            labels = database.get("labels", "named")
            entry = {"id": question["id"], "type": question["type"], "database": database["name"],
                     "labels": labels, "today": args.today.isoformat(),
                     "question": " ".join(fill(question["question"], params).split())}
            behaviour = question.get("labels", {}).get(labels)
            try:
                if behaviour:
                    # Here the question has no answer to state: only the behaviour counts.
                    entry.update(readings=[], forbid=[], rubric=" ".join(fill(behaviour, params).split()))
                else:
                    ask = lambda case: query(models, database["name"], deployment["time_zone"], case, args.today, params)
                    readings = [question.get("expect", []), *question.get("alternatives", [])]
                    entry["readings"] = [[ask(case) for case in reading] for reading in readings if reading]
                    entry["forbid"] = [ask(case) for case in question.get("forbid", [])]
                    if question.get("rubric"):
                        entry["rubric"] = " ".join(fill(question["rubric"], params).split())
                    if question.get("if_empty"):
                        entry["if_empty"] = " ".join(fill(question["if_empty"], params).split())
            except (RuntimeError, KeyError) as error:
                failures += 1
                print(f"FAILED {question['id']} over {database['name']}: {error}", file=sys.stderr)
                continue
            entries.append(entry)
    json.dump(entries, sys.stdout, indent=1, default=str)
    print()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
