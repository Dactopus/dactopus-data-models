"""Ask a model questions with dactopus-ossie-clickhouse and compare the answers with
expected rows; tests/<source>/questions.yaml hold the questions."""
import json
import math
import pathlib
import subprocess
import sys

FLAGS = (("-m", "metrics"), ("-d", "dimensions"), ("-f", "filters"), ("-o", "order"))


def questions(source, windows=False):
    """The cases of tests/<source>/questions.yaml, or its window_cases.

    A case is a mapping: metrics, dimensions, filters and order (lists,
    absent when empty), limit, and expected, the rows of the answer.
    """
    import yaml  # only the questions need it: GA4 and sensor_community list theirs in Python

    path = pathlib.Path(__file__).resolve().parent / source / "questions.yaml"
    return yaml.safe_load(path.read_text())["window_cases" if windows else "cases"]


def flags(case):
    """The command-line flags of dactopus-ossie-clickhouse query for a case."""
    args = [item for flag, key in FLAGS for value in case.get(key, []) for item in (flag, value)]
    if "limit" in case:
        args += ["-l", str(case["limit"])]
    return args


def case_of(args, expected):
    """A case from the flags of the command line and the expected rows: the form
    GA4's and sensor_community's check_numbers.py still list their questions in."""
    case = {}
    for (flag, key), values in ((f, [args[i + 1] for i in range(0, len(args), 2) if args[i] == f[0]]) for f in FLAGS):
        if values:
            case[key] = values
    if "-l" in args:
        case["limit"] = int(args[args.index("-l") + 1])
    return {**case, "expected": expected}


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return a is not None and b is not None and math.isclose(a, b, rel_tol=1e-9)
    return a == b


def ask(model, case):
    """The answer's rows, or the error text, from dactopus-ossie-clickhouse
    (the database is $OSSIE_CLICKHOUSE_URL, the zone $OSSIE_CLICKHOUSE_TIME_ZONE)."""
    out = subprocess.run(["dactopus-ossie-clickhouse", "query", model, *flags(case), "--json"],
                         capture_output=True, text=True)
    return json.loads(out.stdout) if out.returncode == 0 else out.stderr.strip()


def matches(got, expected):
    return isinstance(got, list) and len(got) == len(expected) and all(
        g.keys() == e.keys() and all(same(g[k], e[k]) for k in e) for g, e in zip(got, expected))


def check(model, cases, ask=ask, quit=True):
    """Ask each case with ask(model, case); print the ones that differ and the count.

    Exits with 1 if any differ, else 0; with quit=False returns the number that differ.
    """
    failed = 0
    cases = [case_of(*case) if isinstance(case, tuple) else case for case in cases]
    for case in cases:
        got = ask(model, case)
        if not matches(got, case["expected"]):
            failed += 1
            print(f"FAIL {' '.join(flags(case))}\n  expected {case['expected']}\n  got      {got}")
    print(f"{len(cases) - failed} of {len(cases)} questions match")
    if quit:
        sys.exit(1 if failed else 0)
    return failed
