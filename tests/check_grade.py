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
for space in ("\u00a0", "\u202f", "\u2009"):
    check(f"thousands by U+{ord(space):04X}", found(f"Net revenue was 20{space}907.74 USD."), [20907.74])
    check(f"U+{ord(space):04X} before a currency sign", found(f"Net revenue: −$1{space}234{space}567.5"), [-1234567.5])
    check(f"U+{ord(space):04X} with a percent", found(f"A share of 1{space}250.5%"), [1250.5])
check("plain space parts numbers", found("Tee 3 450 sold"), [3, 450])
check("no-break space after a group", found("Cap: 12\u00a0orders, 4\u202fcaps"), [12, 4])
for sep in (",", "\u00a0"):
    check(f"question's number as the last group by {sep!r}",
          found(f"Store A: 1{sep}500 orders", "Which stores have more than 500 orders?"), [1500])
    check(f"day of a month before a group by {sep!r}", found(f"Net revenue in December 1{sep}234.50 USD"), [1234.5])
    check(f"top N before a group by {sep!r}", found(f"The top 10{sep}000 orders", "the top 10 orders"), [10000])

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

# An expression over metrics comes back under its name: its value is stated, the
# share as a percentage.
share = entry([{"query": {"metrics": ["orders.order_count FILTER (WHERE orders.discount_code_count > 0)"
                                      " / orders.order_count AS discount_code_share"]},
                "rows": [{"discount_code_share": 0.0806}]}])
check("expression stated", grade.check_numbers(share, "8.1% of orders used a code"), (True, "", []))
check("expression missing", grade.check_numbers(share, "37 of 459 orders used a code")[0], False)
check("expression empty", grade.check_numbers(entry([{"query": share["readings"][0][0]["query"],
                                                      "rows": [{"discount_code_share": None}]}]), "none"), None)

# A change asked as a rise or a fall: with `unsigned`, its value with or without its sign.
fall = {"metrics": ["a - b AS revenue_change", "(a - b) / b AS revenue_change_rate"]}
change = {"query": fall, "rows": [{"revenue_change": -82051.35, "revenue_change_rate": -0.8296}]}
check("signed change", grade.check_numbers(entry([change]), "−82,051.35 USD, −83%")[0], True)
check("unsigned change refused", grade.check_numbers(entry([change]), "down 82,051.35 USD, or 83%")[0], False)
unsigned = {**change, "query": {**fall, "unsigned": True}}
check("unsigned change", grade.check_numbers(entry([unsigned]), "down 82,051.35 USD, or 83%")[0], True)
check("unsigned keeps the value", grade.check_numbers(entry([unsigned]), "down 82,051 USD, or 85%")[0], False)
rise = {"query": {**fall, "unsigned": True}, "rows": [{"revenue_change": 82051.35, "revenue_change_rate": 0.8296}]}
check("unsigned rise", grade.check_numbers(entry([rise]), "up 82,051.35 USD, or 83%")[0], True)
check("unsigned rise with a minus", grade.check_numbers(entry([rise]), "−82,051.35 USD, −83%")[0], False)

# Forbidden numbers: a sum over two currencies, unless a reading states it too.
forbidden = entry([rows(100, 200, metric="orders.net_revenue")], forbid=[rows(300, metric="orders.net_revenue")])
check("forbidden stated", grade.check_numbers(forbidden, "100 USD and 200 EUR, 300 in all")[0], False)
check("forbidden not stated", grade.check_numbers(forbidden, "100 USD and 200 EUR"), (True, "", []))

# Tied rows at a limit: any of them may be listed, and their value is stated.
tied = entry([{"query": {}, "rows": [{"title": "Cap", "orders.order_count": 3},
                                     {"title": "Tee", "orders.order_count": 3}], "tied": True}])
check("tied names not required", grade.check_numbers(tied, "Hat: 3 orders"), (True, "", []))

# Numbers not from a query: what the tools returned, the question, zero, a scale, rounding.
def result(*rows, **extra):
    return json.dumps({"columns": ["x"], "rows": [list(r) for r in rows], "row_count": len(rows), **extra})


tools = [result(("shop_us", 26), ("woo_eu", 8)), result(("Knife (KNI-064)", 0.2441)),
         json.dumps({"name": "commerce", "description": "Repeat orders within 30, 60 or 90 days."}),
         json.dumps({"error": "Code: 38. Cannot parse date"})]
spend = entry([rows(26)])
spend["question"] = "Which customers spent over 5,000?"


def unsourced(answer, tool_results=tools, entry_=spend):
    return grade.unsourced(entry_, answer, tool_results)


check("from rows", unsourced("shop_us 26, woo_eu 8"), [])
check("a total added up", unsourced("shop_us 26, woo_eu 8, 34 in all"), ["34"])
check("a difference", unsourced("18 more in shop_us"), ["18"])
check("share as percent", unsourced("a share of 24.4%"), [])
check("a fall as percent", unsourced("down 24.4%", [result((-0.2441,))]), [])
check("a share worked out", unsourced("76% in shop_us"), ["76%"])
check("number in a text value", unsourced("Knife (KNI-064)"), [])
check("count of rows", unsourced("2 stores"), [])
check("model description", unsourced("within 30, 60 or 90 days"), [])
check("error gives none", unsourced("code 38"), ["38"])
check("question's number", unsourced("nobody spent over 5,000"), [])
check("zero", unsourced("woo_eu: 0 refunds"), [])
check("sign", unsourced("refunds of −26"), [])
check("rounded to hundreds", unsourced("about 2,600 minutes", [result((2610,))]), [])
check("rounded wrong", unsourced("about 2,700 minutes", [result((2610,))]), ["2,700"])
check("small whole number not rounded", unsourced("about 30 minutes", [result((26,))]), ["30"])
check("thousands shortened", unsourced("based on 109k visits", [result((109297,))]), [])
scaled = entry([{"query": {"scale": 0.01}, "rows": [{"air.pressure": 101050}]}])
check("scale of the expected answer", unsourced("1010.5 hPa", [result((101050,))], scaled), [])
check("not scaled elsewhere", unsourced("1010.5 hPa", [result((101050,))]), ["1,010.5"])
check("dates and ranks", unsourced("| 11 | Tee | 26 |\n2026-09, 2026‑11‑09, 11-09 12:29, the 31st, "
                                   "1–11 Nov, Nov 1–11, Mon 2"), [])
check("weekday words only", unsourced("Monthly 45, Sunglasses 3, Wednesday 4"), ["45", "3"])
check("shortened, not a year", unsourced("about 2k visits", [result((2610,))]), ["2,000"])
check("a date gives no day", unsourced("21 orders", [result(("2026-10-21T00:00:00-04:00", 5))]), ["21"])
check("text after a line break", unsourced("30 days", [json.dumps({"description": "Repeat orders.\n30 days"})]), [])
check("length of a period", unsourced("November is only 20 days in; the 89 days before it; a 31-day month"), [])
check("days with decimals, from a query", unsourced("On average 23.6 days.", [result((23.6,))]), [])
check("days with decimals, worked out", unsourced("On average 23.6 days.", [result((20,))]), ["23.6"])
check("days in thousands", unsourced("open for 1,250 days", [result((20,))]), ["1,250"])
check("hours since a time", unsourced("quiet for 31 hours"), ["31"])
check("code", unsourced('Ran `INTERVAL \'4\' MONTH`:\n```json\n{"limit": 20}\n```\n7 orders'), ["7"])
check("model with a clock error", unsourced("30 days", [json.dumps({"description": "Within 30 days",
                                                                    "error": "ClickHouse: down"})]), [])

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

# With tool_results: a number not from a query makes the answer wrong.
answers[0].update(answer="5 orders, 7 last week", tool_results=[result((5,))])
answers[1]["tool_results"] = []
with tempfile.TemporaryDirectory() as directory:
    paths = [pathlib.Path(directory, "expected.json"), pathlib.Path(directory, "answers.jsonl")]
    paths[0].write_text(json.dumps(expected))
    paths[1].write_text("".join(json.dumps(a) + "\n" for a in answers))
    out = subprocess.run([sys.executable, str(ROOT / "evals" / "grade.py"), *map(str, paths), "--no-judge"],
                         capture_output=True, text=True)
verdicts = [json.loads(line) for line in out.stdout.splitlines()]
check("sourced verdicts", [(v["passed"], v["reasons"], v["not_from_queries"]) for v in verdicts],
      [(False, ["not from a query 7"], ["7"]), (None, ["not graded: needs a judge for: Asks which store is meant."], [])])
check("sourced totals", out.stderr.splitlines()[-1] if out.stderr else "",
      "all: 0 of 1 right, 1 not graded, 1 wrong for numbers not from a query")

for failure in failures:
    print(failure)
print(f"{len(failures)} failed" if failures else "grade.py: every case passed")
sys.exit(1 if failures else 0)
