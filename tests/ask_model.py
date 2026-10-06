"""Ask a model questions with ossie-clickhouse and compare the answers with
expected rows; tests/<source>/check_numbers.py hold the questions."""
import json
import math
import subprocess
import sys


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return a is not None and b is not None and math.isclose(a, b, rel_tol=1e-9)
    return a == b


def check(model, cases):
    failed = 0
    for args, expected in cases:
        out = subprocess.run(["ossie-clickhouse", "query", model, *args, "--json"],
                             capture_output=True, text=True)
        got = json.loads(out.stdout) if out.returncode == 0 else out.stderr.strip()
        ok = isinstance(got, list) and len(got) == len(expected) and all(
            g.keys() == e.keys() and all(same(g[k], e[k]) for k in e) for g, e in zip(got, expected))
        if not ok:
            failed += 1
            print(f"FAIL {' '.join(args)}\n  expected {expected}\n  got      {got}")
    print(f"{len(cases) - failed} of {len(cases)} questions match")
    sys.exit(1 if failed else 0)
