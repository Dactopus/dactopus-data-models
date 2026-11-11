# /// script
# dependencies = ["anthropic", "pydantic"]
# ///
"""Grade an agent's answers against the expected answers of evals/reference.py.

    uv run evals/grade.py expected.json answers.jsonl > verdicts.jsonl

answers.jsonl holds one JSON object per line: {"id": ..., "database": ..., "answer": ...},
the question's id and database as in expected.json and the agent's final answer as text.

An answer is right when it states every number of one reading of the question (and
every text value, such as a product's title or a currency's code), states no number
the question forbids, and, where the question has a rubric, a reviewing model finds
that it does what the rubric says. A number is found at the precision the answer
shows it: 107.82 and 108 both state 107.8181...; a share of 0.244 may be written as
24.4%. Where every expected query is empty, the rubric is the question's if_empty, or
that the answer says there is none.

The reviewing model is a Claude model (--judge-model, default claude-haiku-5-5) through
the Anthropic API: set ANTHROPIC_API_KEY. Questions without a rubric need no key.
Prints one verdict per line and, on stderr, the count of right answers per type.
"""
import argparse
import collections
import json
import math
import re
import sys

NUMBER = re.compile(r"(?<![\w.])([-−]?)(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?\s*(%?)")
ZERO = re.compile(r"\b(zero|none|nothing)\b", re.I)
RATIO = re.compile(r"rate|share")
MONTH = (r"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?")
# Numbers that are not values: dates, times, years, the day in "October 3" or
# "3rd of October", list markers at the start of a line.
NOT_VALUES = [re.compile(p, re.I | re.M) for p in (
    r"\b\d{4}-\d\d-\d\d(?:[ T]\d\d:\d\d(?::\d\d)?(?:[+-]\d\d:?\d\d|Z)?)?",
    r"\b\d{1,2}:\d\d(?::\d\d)?\b", r"\b(?:19|20)\d\d\b",
    MONTH + r"\s+\d{1,2}(?:st|nd|rd|th)?\b", r"\b\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?" + MONTH,
    r"^\s*(?:[-*]\s*)?\d{1,2}[.)]\s")]
DEFAULT_IF_EMPTY = "Says there is none: no such rows, or zero."


def strip_not_values(text, question):
    """The text without the numbers that are not values, nor those the question
    asks with (the 7 of "last 7 days", the 10 of "top 10")."""
    for pattern in NOT_VALUES:
        text = pattern.sub(" ", text)
    for number, word in re.findall(r"(\d+)\s*(%|[a-z]+)", question, re.I):
        text = re.sub(rf"\b{number}\s*{re.escape(word)}", " ", text, flags=re.I)
    for word, number in re.findall(r"\b(top|last|past|bottom|first|within)\s+(\d+)", question, re.I):
        text = re.sub(rf"\b{word}\s+{number}\b", " ", text, flags=re.I)
    return text


def numbers(text):
    """The numbers of a text: (value, decimals shown, written as a percentage)."""
    found = []
    for sign, whole, fraction, percent in NUMBER.findall(text):
        value = float(whole.replace(",", "") + (f".{fraction}" if fraction else ""))
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
    """Text for finding a name in an answer: lower case, without punctuation, a
    leading article or repeated spaces ("The Minimal Snowboard" is in "Minimal
    snowboard:")."""
    text = re.sub(r"[^\w\s]", " ", text.lower())
    return " ".join(re.sub(r"^\s*(the|a|an)\s+", "", text).split())


def is_empty(result):
    """A query with no row, or only empty metric values."""
    return all(v is None for row in result["rows"] for k, v in row.items() if "." in k)


def describe(query):
    return ", ".join(query.get("metrics", [])) + "".join(f" where {f}" for f in query.get("filters", []))


def required(reading):
    """The metric values and text values a reading's answer must state."""
    values, texts = [], []
    for result in reading:
        counts = result["query"].get("numbers", True)
        for row in result["rows"]:
            for key, value in row.items():
                if "." in key and isinstance(value, (int, float)) and not isinstance(value, bool):
                    if counts:
                        values.append((key, float(value)))
                elif (key != "source_id" and not result.get("tied") and isinstance(value, str)
                      and not re.fullmatch(r"[\d\-:T+ .]+", value)):
                    texts.append(value)
    return values, texts


def check_numbers(entry, answer):
    """None when the question has no numbers, or every query of its first reading is
    empty; else (passed, what is missing or forbidden, the empty queries of the
    reading the answer states)."""
    if not entry["readings"] or all(is_empty(r) for r in entry["readings"][0]):
        return None
    text = strip_not_values(answer, entry["question"])
    found = numbers(text)
    misses = []
    for reading in entry["readings"]:
        if all(is_empty(r) for r in reading):
            continue
        values, texts = required([r for r in reading if not is_empty(r)])
        missing = [f"{m} {v:g}" for m, v in values if not states(text, found, v, m)]
        missing += [t for t in texts if plain(t) not in plain(answer)]
        if not missing:
            empties = [describe(r["query"]) for r in reading if is_empty(r)]
            break
        misses.append(missing)
    else:
        return False, "missing " + " | ".join(", ".join(m) for m in misses), []
    allowed = [v for reading in entry["readings"] for _, v in required(reading)[0]]
    forbidden = [(m, v) for m, v in required(entry["forbid"])[0]
                 if v != 0 and not any(math.isclose(v, a, rel_tol=1e-9) for a in allowed)]
    stated = [f"{m} {v:g}" for m, v in forbidden if states(text, found, v, m)]
    if stated:
        return False, "states forbidden " + ", ".join(stated), []
    return True, "", empties


def judge(client, model, entry, criterion, answer):
    from pydantic import BaseModel

    class Verdict(BaseModel):
        passed: bool
        reason: str

    prompt = (
        "An agent answered a store owner's question through a semantic model of the store's data. "
        "Decide whether the answer meets the criterion. Judge only the criterion, not the style, "
        "and not numbers the criterion does not mention.\n\n"
        f"<question>{entry['question']}</question>\n<criterion>{criterion}</criterion>\n"
        f"<answer>{answer}</answer>")
    response = client.messages.parse(model=model, max_tokens=2000, output_format=Verdict,
                                     messages=[{"role": "user", "content": prompt}])
    if response.stop_reason == "refusal" or response.parsed_output is None:
        return False, f"the reviewing model gave no verdict ({response.stop_reason})"
    return response.parsed_output.passed, response.parsed_output.reason


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("expected", help="the output of evals/reference.py")
    parser.add_argument("answers", help="JSON lines: id, database, answer")
    parser.add_argument("--judge-model", default="claude-haiku-5-5")
    args = parser.parse_args()

    expected = {(e["id"], e["database"]): e for e in json.load(open(args.expected))}
    client = None
    totals = collections.defaultdict(lambda: [0, 0])
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
            if client is None:
                import anthropic

                client = anthropic.Anthropic()
            passed, reason = judge(client, args.judge_model, entry, criterion, answer)
            verdict["passed"] = passed
            verdict["reasons"].append(("" if passed else "rubric: ") + reason)
        totals[entry["type"]][0] += verdict["passed"]
        totals[entry["type"]][1] += 1
        print(json.dumps(verdict, ensure_ascii=False), flush=True)
    for kind, (right, asked) in sorted(totals.items()):
        print(f"{kind}: {right} of {asked}", file=sys.stderr)
    right = sum(r for r, _ in totals.values())
    print(f"all: {right} of {sum(a for _, a in totals.values())}", file=sys.stderr)


if __name__ == "__main__":
    main()
