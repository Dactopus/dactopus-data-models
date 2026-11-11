"""Check evals/grade.py on hand-written answers: which numbers and names it finds in
an answer, which it leaves out as dates or the question's own, and the verdict it
gives a question's readings, forbidden numbers and empty queries. No server and no
reviewing model needed. Run from the repository root:

    uv run tests/check_grade.py
"""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("grade", ROOT / "evals" / "grade.py")
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)

failures = []


def check(name, got, want):
    if got != want:
        failures.append(f"{name}: got {got!r}, want {want!r}")


def found(answer, question="How did the store do?"):
    """The values the grader finds in an answer."""
    return [value for value, _, _ in grade.numbers(grade.strip_not_values(answer, question))]


# Numbers: separators, signs before a currency sign, percentages.
check("thousands", found("Net revenue was 13,693.68 USD."), [13693.68])
check("sign before currency", found("Net revenue: −$8,807.61"), [-8807.61])
check("hyphen of a range", found("between 5-10 orders"), [5, 10])
check("percentage", found("A refund rate of 24.4 %"), [24.4])

# Not values: dates, times, years, days of a month, list markers, the question's numbers.
check("ISO date", found("On 2026-10-03 there were 44 orders"), [44])
check("time", found("at 14:30 UTC, 3 orders"), [3])
check("year", found("In October 2026, 12 orders"), [12])
check("day after month", found("On Oct. 3 we had 5"), [5])
check("day before month", found("the 3rd of October: 5"), [5])
check("list marker", found("1. Tee: 3\n2) Cap: 4"), [3, 4])
check("question's own numbers", found("In the last 7 days: 12 orders", "How many orders in the last 7 days?"),
      [12])
check("question's top N", found("Your top 5 products sold 40 units", "What are my top 5 products?"), [40])

# Values that look like dates in part, and stay.
check("word starting like a month", found("Net revenue decreased 12% from last month"), [12])
check("word holding a month", found("The 4 separate stores; marketing 40 orders"), [4, 40])
check("amount like a year", found("Revenue was 1950.00 USD"), [1950])
check("amount after currency", found("$2025 in total"), [2025])

# A value is stated at the precision the answer shows it.
values = grade.numbers("107.82 and 108")
check("rounded to 2 decimals", grade.states("", values[:1], 107.8181, "orders.net_revenue"), True)
check("rounded to a whole", grade.states("", values[1:], 107.8181, "orders.net_revenue"), True)
check("wrong value", grade.states("", grade.numbers("107.9"), 107.8181, "orders.net_revenue"), False)
check("ratio as percent", grade.states("", grade.numbers("24.4%"), 0.2441, "orders.refund_rate"), True)
check("ratio as fraction", grade.states("", grade.numbers("0.24"), 0.2441, "orders.refund_rate"), True)
check("ratio as bare whole", grade.states("", grade.numbers("24"), 0.2441, "orders.refund_rate"), False)
check("zero in words", grade.states("No refunds: none.", [], 0, "orders.refunded_amount"), True)

# Names: whole words, aliases, an article, a category's leaf, a URL's tail.
leaves = {"Dresses": 1, "Tee": 1}
check("whole words", grade.names("Thirteen sold", ("Tee", []), leaves), False)
check("case and article", grade.names("minimal snowboard: 4", ("The Minimal Snowboard", []), leaves), True)
check("alias", grade.names("Returning customers: 7", ("repeat", ["Returning"]), leaves), True)
check("category leaf", grade.names("Dresses sold 4", ("Clothing > Dresses", []), leaves), True)
check("URL tail", grade.names("…/Apparel/Dino+Game+Tee had 3",
                              ("https://shop.example/Apparel/Dino+Game+Tee", []), leaves), True)


def rows(*values, metric="orders.order_count", **dimensions):
    return {"query": {}, "rows": [{**dimensions, metric: v} for v in values]}


EMPTY = {"query": {}, "rows": []}


def entry(*readings, forbid=()):
    return {"question": "How many orders?", "readings": list(readings), "forbid": list(forbid)}


# Readings: any one of them, with all its numbers and names.
two = entry([rows(5, currency="USD")], [rows(7, currency="USD")])
check("first reading", grade.check_numbers(two, "5 orders in USD"), (True, "", []))
check("alternative reading", grade.check_numbers(two, "7 orders in USD"), (True, "", []))
check("no reading", grade.check_numbers(two, "6 orders in USD")[0], False)
check("name missing", grade.check_numbers(two, "5 orders")[0], False)

# An empty reading: the answer that states no reading with rows must say there is none.
check("all empty", grade.check_numbers(entry([EMPTY]), "none"), None)
mixed = entry([rows(5)], [EMPTY])
check("states the reading with rows", grade.check_numbers(mixed, "5 orders"), (True, "", []))
check("states none of them", grade.check_numbers(mixed, "No orders in that period"), None)
check("empty first reading", grade.check_numbers(entry([EMPTY], [rows(5)]), "5 orders"), (True, "", []))
# A reading with an empty query: the answer says there is none for that part.
part = entry([rows(5), {"query": {"metrics": ["refunds.refund_count"]}, "rows": []}])
check("empty part", grade.check_numbers(part, "5 orders"), (True, "", ["refunds.refund_count"]))

# Forbidden numbers: a sum over two currencies, unless a reading states it too.
forbidden = entry([rows(100, 200, metric="orders.net_revenue")], forbid=[rows(300, metric="orders.net_revenue")])
check("forbidden stated", grade.check_numbers(forbidden, "100 USD and 200 EUR, 300 in all")[0], False)
check("forbidden not stated", grade.check_numbers(forbidden, "100 USD and 200 EUR"), (True, "", []))

# Tied rows at a limit: any of them may be listed, and their value is stated.
tied = entry([{"query": {}, "rows": [{"title": "Cap", "orders.order_count": 3},
                                     {"title": "Tee", "orders.order_count": 3}], "tied": True}])
check("tied names not required", grade.check_numbers(tied, "Hat: 3 orders"), (True, "", []))

# A judge command prints true or false; a string stops the run.
judge = grade.command_judge("""echo '{"passed": false, "reason": "no period"}'""")
check("judge command", judge({}), (False, "no period"))
try:
    grade.command_judge("""echo '{"passed": "false"}'""")({})
    failures.append("judge command with a string: no error")
except SystemExit:
    pass

# The whole run, numbers only: one right, one wrong, one that needs a judge.
expected = [{"id": "q", "database": "d", "type": "total", **mixed},
            {"id": "r", "database": "d", "type": "total", "readings": [], "forbid": [],
             "question": "Which store?", "rubric": "Asks which store is meant."}]
answers = [{"id": "q", "database": "d", "answer": "5 orders"},
           {"id": "r", "database": "d", "answer": "brand_a"}]
with tempfile.TemporaryDirectory() as directory:
    paths = [pathlib.Path(directory, "expected.json"), pathlib.Path(directory, "answers.jsonl")]
    paths[0].write_text(json.dumps(expected))
    paths[1].write_text("".join(json.dumps(a) + "\n" for a in answers))
    out = subprocess.run([sys.executable, str(ROOT / "evals" / "grade.py"), *map(str, paths), "--no-judge"],
                         capture_output=True, text=True)
check("run exit code", out.returncode, 0)
check("run verdicts", [json.loads(line)["passed"] for line in out.stdout.splitlines()], [True, None])
check("run totals", out.stderr.splitlines()[-1] if out.stderr else "", "all: 1 of 1 right, 1 not graded")

for failure in failures:
    print(failure)
print(f"{len(failures)} failed" if failures else "grade.py: every case passed")
sys.exit(1 if failures else 0)
