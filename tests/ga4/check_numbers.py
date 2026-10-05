"""Ask the web_analytics model questions over tests/ga4/fixture.sql and compare
the answers with numbers derived by hand from those rows.

Run from the repository root after loading the fixture (the query parameter
db names the input database, as in .github/workflows/ci.yml) and building
the GA4 package; $OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the
package's target database, e.g. http://127.0.0.1:8123/dactopus:

    python3 tests/ga4/check_numbers.py

Sessions in the fixture: u1.100, u1.200, u2.300, u3.400, u5.300 (u4's events
have no session id). Purchases: T1 (sent twice, counts once), two without a
transaction id in u2.300, T9 without a value in u3.400, T4 outside any
session.
"""
import json
import math
import subprocess
import sys

MODEL = "entities/web_analytics.yaml"

CASES = [
    # 5 sessions; engaged: u1.100 ('1') and u1.200 (1); with a purchase:
    # u1.100, u2.300, u3.400; users u1, u2, u3, u5 (u4 has no session), of
    # whom u1, u2, u3 bought.
    (["-m", "sessions", "-m", "engaged_sessions", "-m", "engagement_rate", "-m", "users",
      "-m", "session_conversion_rate", "-m", "user_conversion_rate"],
     [{"sessions": 5, "engaged_sessions": 2, "engagement_rate": 0.4, "users": 4,
       "session_conversion_rate": 0.6, "user_conversion_rate": 0.75}]),
    # Purchases: T1 once + 2 in u2.300 + T9 + T4 = 5. Revenue 100 + 50 + 30
    # + 20 = 200, T9 has none; average over the 4 with a value = 50.
    (["-m", "purchases", "-m", "revenue", "-m", "revenue_usd", "-m", "average_order_value"],
     [{"purchases": 5, "revenue": 200, "revenue_usd": 220, "average_order_value": 50}]),
    # The last-click record wins (u1.100 newsletter, not google); old exports
    # take the session's first source (u1.200 google/organic, u2.300
    # google/cpc); none at all is (not set) (u3.400, u5.300).
    (["-m", "sessions", "-d", "sessions.source", "-o", "sessions.source"],
     [{"source": "(not set)", "sessions": 2}, {"source": "google", "sessions": 2},
      {"source": "newsletter", "sessions": 1}]),
    # T9 has no value: (not set) has no revenue. T4 has no session, so no
    # source either.
    (["-m", "revenue", "-d", "sessions.source_medium", "-o", "sessions.source_medium"],
     [{"source_medium": "(not set) / (not set)", "revenue": None},
      {"source_medium": "google / cpc", "revenue": 80},
      {"source_medium": "newsletter / email", "revenue": 100},
      {"source_medium": None, "revenue": 20}]),
    # Two currencies: EUR is T1 100 + u2.300's 50 + 30 = 180 over 3
    # purchases, GBP is T4 20; T9 has neither value nor currency. The total
    # of 200 above adds both, which is why the model breaks revenue down by
    # currency.
    (["-m", "purchases", "-m", "revenue", "-d", "purchases.currency", "-o", "purchases.currency"],
     [{"currency": "EUR", "purchases": 3, "revenue": 180},
      {"currency": "GBP", "purchases": 1, "revenue": 20},
      {"currency": None, "purchases": 1, "revenue": None}]),
    # u1.200 crosses midnight and belongs to March 1.
    (["-m", "sessions", "-d", "sessions.session_date", "-o", "sessions.session_date"],
     [{"session_date": "2025-03-01", "sessions": 2}, {"session_date": "2025-03-02", "sessions": 3}]),
    (["-m", "purchases", "-d", "purchases.purchase_date", "-o", "purchases.purchase_date"],
     [{"purchase_date": "2025-03-01", "purchases": 1}, {"purchase_date": "2025-03-02", "purchases": 4}]),
    # 18 events, u4's included; 6 page_view events, but 5 page views in
    # sessions: u4's is in no session.
    (["-m", "events"], [{"events": 18}]),
    (["-m", "events", "-f", "events.event_name = 'page_view'"], [{"events": 6}]),
    (["-m", "page_views"], [{"page_views": 5}]),
]


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return a is not None and b is not None and math.isclose(a, b, rel_tol=1e-9)
    return a == b


def main():
    failed = 0
    for args, expected in CASES:
        out = subprocess.run(["ossie-clickhouse", "query", MODEL, *args, "--json"],
                             capture_output=True, text=True)
        got = json.loads(out.stdout) if out.returncode == 0 else out.stderr.strip()
        ok = isinstance(got, list) and len(got) == len(expected) and all(
            g.keys() == e.keys() and all(same(g[k], e[k]) for k in e) for g, e in zip(got, expected))
        if not ok:
            failed += 1
            print(f"FAIL {' '.join(args)}\n  expected {expected}\n  got      {got}")
    print(f"{len(CASES) - failed} of {len(CASES)} questions match")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
