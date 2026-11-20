# /// script
# dependencies = ["anthropic", "pydantic"]
# ///
"""Grade an agent's answers against the expected answers of evals/reference.py.

    uv run evals/grade.py expected.json answers.jsonl > verdicts.jsonl

answers.jsonl holds one JSON object per line: {"id": ..., "database": ..., "answer": ...},
the question's id and database as in expected.json and the agent's final answer as text.
An optional "tool_results", the text of each tool result of the session, adds to each
verdict "not_from_queries": the answer's numbers that no tool result gives (unsourced()).
The verdict does not depend on it.

An answer is right when it states every number of one reading of the question (and
every text value, such as a product's title or a currency's code, as whole words or as
an alias the query gives), states no number
the question forbids, and, where the question has a rubric, a reviewing model finds
that it does what the rubric says. A number is found at the precision the answer
shows it: 107.82 and 108 both state 107.8181...; a share of 0.244 may be written as
24.4%. Where every query of a reading is empty and the answer states no reading with
rows, the rubric is the question's if_empty, or that the answer says there is none.

A rubric is judged by a reviewing model. By default it is a Claude model
(--judge-model, default claude-haiku-5-5) through the Anthropic API: set
ANTHROPIC_API_KEY. --judge-command runs a command of your own instead, through a shell,
once per answer to judge: it gets {"question", "criterion", "answer", "prompt"} as JSON
on stdin, where prompt is the text the Claude judge gets, and prints {"passed": true or
false, "reason": "..."} as JSON. --no-judge checks numbers only: an answer that needs a
rubric gets "passed": null, not graded. Judges differ on answers at the edge of a
rubric: compare runs graded by the same judge only.

Prints one verdict per line and, on stderr, the count of right answers per type.
"""
import argparse
import collections
import json
import math
import re
import subprocess
import sys

# A number with its sign, which may stand before a currency sign (−$8,807.61). Thousands
# are grouped by a comma or a no-break (U+00A0), narrow no-break (U+202F) or thin (U+2009)
# space; a plain space is not a separator, as two numbers in a row may be apart by one.
THOUSANDS = ",\u00a0\u202f\u2009"
# Not inside a grouped number: no digit or separator before, no group after.
APART = rf"(?<![\w.{THOUSANDS}])"
WHOLE = rf"(?![{THOUSANDS}]\d)"
NUMBER = re.compile(rf"(?<![\w.])([-−]?)(?:[$€£¥]\s?)?(\d{{1,3}}(?:[{THOUSANDS}]\d{{3}})+|\d+)(?:\.(\d+))?\s*(%?)")
ZERO = re.compile(r"\b(zero|none|nothing)\b", re.I)
RATIO = re.compile(r"rate|share")
# A month's name or abbreviation as a whole word ("Dec", not the start of "decreased").
MONTH = (r"\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?"
         r"|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\b\.?")
# Numbers that are not values: dates, times, years (not an amount such as 1950.00 or
# $2025), the day in "October 3" or "3rd of October", list markers at the start of a line.
NOT_VALUES = [re.compile(p, re.I | re.M) for p in (
    r"\b\d{4}-\d\d-\d\d(?:[ T]\d\d:\d\d(?::\d\d)?(?:[+-]\d\d:?\d\d|Z)?)?",
    r"\b\d{1,2}:\d\d(?::\d\d)?\b", r"(?<![$€£¥.,])\b(?:19|20)\d\d\b(?![.,]\d|\s*%)",
    MONTH + r"\s+\d{1,2}(?:st|nd|rd|th)?\b" + WHOLE, r"\b\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?" + MONTH,
    r"^\s*(?:[-*]\s*)?\d{1,2}[.)]\s")]
# Not values either where the check is whether a number comes from a query: a month
# (2026-09), a date with a no-break hyphen or without its year (11-09), a day as an
# ordinal (the 31st) or in "1–11 Nov", "Nov 1–11" or "Mon 2", the rank in a table's
# first column. Grading leaves them in: a right answer may state a
# value nowhere else ("1–10 November ... One landed on").
NOT_SOURCED = [re.compile(p, re.I | re.M) for p in (
    r"\b\d{4}[-‑]\d\d(?:[-‑]\d\d)?\b", r"\b(?:0[1-9]|1[0-2])[-‑](?:0[1-9]|[12]\d|3[01])\b",
    r"\b\d{1,2}(?:st|nd|rd|th)\b",
    MONTH + r"\s+\d{1,2}\s*[–-]\s*\d{1,2}\b" + WHOLE,
    r"\b\d{1,2}\s*[–-]\s*(?=\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?" + MONTH + ")",
    r"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\.?\s+\d{1,2}\b" + WHOLE,
    r"^\s*\|\s*\d{1,3}\s*(?=\|)")]
# A number shortened by thousands or millions: 109k, 1.2M.
THOUSANDFOLD = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)([kKM])\b")
DEFAULT_IF_EMPTY = "Says there is none: no such rows, or zero."


def strip_not_values(text, question):
    """The text without the numbers that are not values, nor those the question
    asks with (the 7 of "last 7 days", the 10 of "top 10")."""
    for pattern in NOT_VALUES:
        text = pattern.sub(" ", text)
    for number, word in re.findall(r"(\d+)\s*(%|[a-z]+)", question, re.I):
        text = re.sub(rf"{APART}{number}\s*{re.escape(word)}", " ", text, flags=re.I)
    for word, number in re.findall(r"\b(top|last|past|bottom|first|within)\s+(\d+)", question, re.I):
        text = re.sub(rf"\b{word}\s+{number}\b{WHOLE}", " ", text, flags=re.I)
    return text


def numbers(text):
    """The numbers of a text: (value, decimals shown, written as a percentage)."""
    found = []
    for sign, whole, fraction, percent in NUMBER.findall(text):
        value = float(re.sub(f"[{THOUSANDS}]", "", whole) + (f".{fraction}" if fraction else ""))
        found.append((-value if sign else value, len(fraction), bool(percent)))
    return found


def states(text, found, expected, metric):
    """Whether the answer states the expected value at the precision it shows."""
    if expected == 0:
        return any(value == 0 for value, _, _ in found) or bool(ZERO.search(text))
    for value, decimals, percent in found:
        tolerance = 0.5 * 10 ** -decimals + 1e-9
        if RATIO.search(metric):
            if percent and abs(value - expected * 100) <= tolerance:
                return True
            if not percent and decimals >= 2 and abs(value - expected) <= tolerance:
                return True
        elif abs(value - expected) <= tolerance:
            return True
    return False


def plain(text):
    """Text for finding a name in an answer: lower case, without punctuation (an
    underscore counts as one: pm2_5 is PM2.5), a URL's scheme, a leading article or
    repeated spaces ("The Minimal Snowboard" is in "Minimal snowboard:")."""
    text = re.sub(r"\bhttps?://", " ", text.lower())
    text = re.sub(r"[\W_]+", " ", text)
    return " ".join(re.sub(r"^\s*(the|a|an)\s+", "", text).split())


# The tail of a URL an answer shortened with an ellipsis: …/Apparel/Dino+Game+Tee.
ELIDED = re.compile(r"(?:…|\.\.\.)([^\s|`'\")\]]*/[^\s|`'\")\]]*\w)")


def names(answer, name, leaves):
    """Whether the answer names a text value, as whole words ("Tee" is not in
    "Thirteen"): by the value itself or one of its aliases; a category path
    (Clothing > Dresses) by its last category alone where no other path of the
    reading ends in that name; a URL also by a tail after an ellipsis."""
    value, aliases = name
    said = f" {plain(answer)} "
    if any(f" {plain(n)} " in said for n in (value, *aliases)):
        return True
    leaf = value.rsplit(" > ", 1)[-1]
    if leaf != value and leaves[leaf] == 1 and f" {plain(leaf)} " in said:
        return True
    if re.match(r"https?://", value):
        url = value.lower().rstrip("/")
        return any(url.endswith(tail.lower().rstrip("/")) for tail in ELIDED.findall(answer))
    return False


def is_empty(result):
    """A query with no row, or only empty metric values."""
    return all(v is None for row in result["rows"] for k, v in row.items() if "." in k)


def describe(query):
    return ", ".join(query.get("metrics", [])) + "".join(f" where {f}" for f in query.get("filters", []))


def required(reading):
    """The metric values a reading's answer must state, and its text values, each with
    the other spellings the query accepts for it (aliases: a code such as US or
    repeat that an answer may write out)."""
    values, texts = [], []
    for result in reading:
        counts = result["query"].get("numbers", True)
        scale = result["query"].get("scale", 1)
        aliases = result["query"].get("aliases", {})
        for row in result["rows"]:
            for key, value in row.items():
                if "." in key and isinstance(value, (int, float)) and not isinstance(value, bool):
                    if counts:
                        values.append((key, float(value) * scale))
                elif (key != "source_id" and not result.get("tied") and isinstance(value, str)
                      and not re.fullmatch(r"[\d\-:T+ .]+", value)):
                    texts.append((value, aliases.get(value, [])))
    return values, texts


def check_numbers(entry, answer):
    """None when the question has no numbers, or every query of a reading is empty and
    the answer states no reading with rows (the answer must then say there is none);
    else (passed, what is missing or forbidden, the empty queries of the reading the
    answer states)."""
    readings = [reading for reading in entry["readings"] if not all(is_empty(r) for r in reading)]
    if not readings:
        return None
    text = strip_not_values(answer, entry["question"])
    found = numbers(text)
    misses = []
    for reading in readings:
        values, texts = required([r for r in reading if not is_empty(r)])
        missing = [f"{m} {v:g}" for m, v in values if not states(text, found, v, m)]
        leaves = collections.Counter(value.rsplit(" > ", 1)[-1] for value in {v for v, _ in texts})
        missing += [value for value, aliases in texts if not names(answer, (value, aliases), leaves)]
        if not missing:
            empties = [describe(r["query"]) for r in reading if is_empty(r)]
            break
        misses.append(missing)
    else:
        if len(readings) < len(entry["readings"]):
            # A reading with no rows: the answer may say there is none.
            return None
        return False, "missing " + " | ".join(", ".join(m) for m in misses), []
    allowed = [v for reading in entry["readings"] for _, v in required(reading)[0]]
    forbidden = [(m, v) for m, v in required(entry["forbid"])[0]
                 if v != 0 and not any(math.isclose(v, a, rel_tol=1e-9) for a in allowed)]
    stated = [f"{m} {v:g}" for m, v in forbidden if states(text, found, v, m)]
    if stated:
        return False, "states forbidden " + ", ".join(stated), []
    return True, "", empties


def sources(tool_results):
    """The numbers the tools returned in the session: every value in the rows of a
    query's result and every number in its text values (a SKU, a title), its count of
    rows, and every number in the text of another result, such as the model's
    descriptions. A result with an error gives none."""
    values = []
    for text in tool_results:
        try:
            data = json.loads(text)
        except ValueError:
            data = None
        if isinstance(data, dict) and "error" in data:
            continue
        if isinstance(data, dict) and isinstance(data.get("rows"), list):
            values.append(float(data.get("row_count", len(data["rows"]))))
            for row in data["rows"]:
                for value in (row.values() if isinstance(row, dict) else row):
                    if isinstance(value, (int, float)) and not isinstance(value, bool):
                        values.append(float(value))
                    elif isinstance(value, str):
                        try:
                            values.append(float(value))
                        except ValueError:
                            values += [number for number, _, _ in numbers(value)]
        else:
            values += [value for value, _, _ in numbers(text)]
    return values


def unsourced(entry, answer, tool_results):
    """The numbers of an answer that come from no tool result of its session: not a
    value of a result at the precision the answer shows (by its absolute value, a share
    as a percentage, times a scale of the expected answer, such as hPa from Pa), nor a
    number of the question, nor zero (a store without a row has zero). From 1,000 up, a
    whole number's trailing zeros are rounding: about 2,600 states 2,610, and 109k states
    109,297."""
    pool = sources(tool_results) + [value for value, _, _ in numbers(entry["question"])]
    scales = {1} | {r["query"].get("scale", 1) for reading in entry["readings"] for r in reading}
    found = []
    text = answer
    for pattern in NOT_SOURCED:
        text = pattern.sub(" ", text)
    text = THOUSANDFOLD.sub(lambda m: str(round(float(m[1]) * {"k": 1e3, "m": 1e6}[m[2].lower()])), text)
    for value, decimals, percent in numbers(strip_not_values(text, entry["question"])):
        if value == 0:
            continue
        whole = str(int(abs(value)))
        zeros = len(whole) - len(whole.rstrip("0")) if not decimals and abs(value) >= 1000 else 0
        tolerance = 0.5 * 10 ** (zeros - decimals) + 1e-9
        if not any(abs(abs(value) - abs(r * scale)) <= tolerance
                   or (percent and abs(value - r * scale * 100) <= tolerance)
                   for r in pool for scale in scales):
            found.append(f"{value:,.{decimals}f}" + ("%" if percent else ""))
    return found


JUDGE_PROMPT = (
    "An agent answered a question about an owner's data through a semantic model of that data. "
    "Decide whether the answer meets the criterion. Judge only the criterion, not the style, "
    "and not numbers the criterion does not mention.\n\n"
    "<question>{question}</question>\n<criterion>{criterion}</criterion>\n<answer>{answer}</answer>")


def claude_judge(model):
    """A judge that asks a Claude model through the Anthropic API."""
    import anthropic
    from pydantic import BaseModel

    # The reason comes first, so that the model reasons before it decides.
    class Verdict(BaseModel):
        reason: str
        passed: bool

    client = anthropic.Anthropic()

    def judge(task):
        response = client.messages.parse(model=model, max_tokens=2000, output_format=Verdict,
                                         messages=[{"role": "user", "content": task["prompt"]}])
        if response.stop_reason == "refusal" or response.parsed_output is None:
            return False, f"the reviewing model gave no verdict ({response.stop_reason})"
        return response.parsed_output.passed, response.parsed_output.reason
    return judge


def command_judge(command):
    """A judge that runs a command of the user's: the task as JSON on stdin, a verdict
    {"passed": true or false, "reason": "..."} as JSON on stdout."""
    def judge(task):
        out = subprocess.run(command, shell=True, input=json.dumps(task), capture_output=True, text=True)
        if out.returncode != 0:
            raise SystemExit(f"the judge command failed: {out.stderr.strip()}")
        verdict = json.loads(out.stdout)
        if not isinstance(verdict.get("passed"), bool):
            raise SystemExit(f"the judge command printed no true or false passed: {out.stdout.strip()}")
        return verdict["passed"], str(verdict.get("reason", ""))
    return judge


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("expected", help="the output of evals/reference.py")
    parser.add_argument("answers", help="JSON lines: id, database, answer")
    parser.add_argument("--judge-model", default="claude-haiku-5-5",
                        help="the Claude model that judges rubrics (default claude-haiku-5-5)")
    parser.add_argument("--judge-command", help="judge rubrics with this command instead (see above)")
    parser.add_argument("--no-judge", action="store_true",
                        help="check numbers only; an answer that needs a rubric is not graded")
    args = parser.parse_args()

    expected = {(e["id"], e["database"]): e for e in json.load(open(args.expected))}
    judge = None
    totals = collections.defaultdict(lambda: [0, 0, 0, 0])  # right, wrong, not graded, unsourced
    sourced = False
    for line in open(args.answers):
        if not line.strip():
            continue
        item = json.loads(line)
        entry = expected[(item["id"], item["database"])]
        answer = item["answer"] or ""
        verdict = {"id": item["id"], "database": item["database"], "passed": True, "reasons": []}
        result = check_numbers(entry, answer)
        criteria = [entry["rubric"]] if entry.get("rubric") else []
        if result is None and entry["readings"]:
            criteria.append(entry.get("if_empty", DEFAULT_IF_EMPTY))
        elif result is not None and not result[0]:
            verdict["passed"] = False
            verdict["reasons"].append(result[1])
        elif result is not None and result[2]:
            # Part of the answer has no rows: that part must say so.
            criteria.append(entry.get("if_empty") or
                            "For " + "; and for ".join(result[2]) + ": says there is none, or zero.")
        criterion = " ".join(criteria)
        if criterion and verdict["passed"]:
            if args.no_judge:
                verdict["passed"] = None
                verdict["reasons"].append("not graded: needs a judge for: " + criterion)
            else:
                if judge is None:
                    judge = (command_judge(args.judge_command) if args.judge_command
                             else claude_judge(args.judge_model))
                task = {"question": entry["question"], "criterion": criterion, "answer": answer,
                        "prompt": JUDGE_PROMPT.format(question=entry["question"], criterion=criterion,
                                                      answer=answer)}
                passed, reason = judge(task)
                verdict["passed"] = passed
                verdict["reasons"].append(("" if passed else "rubric: ") + reason)
        if "tool_results" in item:
            sourced = True
            verdict["not_from_queries"] = unsourced(entry, answer, item["tool_results"] or [])
            totals[entry["type"]][3] += bool(verdict["not_from_queries"])
        column = {True: 0, False: 1, None: 2}[verdict["passed"]]
        totals[entry["type"]][column] += 1
        print(json.dumps(verdict, ensure_ascii=False), flush=True)

    def line(name, right, wrong, open_, unsourced_):
        rest = f", {open_} not graded" if open_ else ""
        rest += f", {unsourced_} with numbers not from a query" if sourced else ""
        print(f"{name}: {right} of {right + wrong} right{rest}", file=sys.stderr)
    for kind, counts in sorted(totals.items()):
        line(kind, *counts)
    line("all", *(sum(c[i] for c in totals.values()) for i in range(4)))


if __name__ == "__main__":
    main()
