"""Ask the commerce model questions over tests/shopify/fixture.sql and compare
the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the
fixture into one database (the query parameter db) and building the Shopify
package over it in the shop's time zone, America/New_York:

    clickhouse client --param_db=shopify_input --multiquery < sources/shopify/input.sql
    clickhouse client --param_db=shopify_input --multiquery < tests/shopify/fixture.sql
    dbt build --project-dir sources/shopify --profiles-dir tests \
        --vars '{shopify_input_database: shopify_input, shopify_timezone: America/New_York}'
    OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York uv run tests/shopify/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus. The model is asked in the
zone it was built in, $OSSIE_CLICKHOUSE_TIME_ZONE.

With --windows it asks about the retention windows instead
(window_cases), over tests/shopify/fixture.sql and tests/shopify/windows.sql
loaded into a database of their own, with no row loaded later.

The questions, the numbers they must answer and how each is derived are in
tests/shopify/questions.yaml.

Orders in the fixture, test orders left out: 1009 (sales, refunded; customer
4's only order) and 1013 (customer 1's, after their last order):
    August     1001 (110), 1002 (80, guest), 1003 (30, 22:00 on August 31
               in New York, September 1 in UTC)
    September  1004 (181, refunded 45 on October 3), 1005 (60, cancelled and
               refunded 60), 1006 (210, refunded 210 at 22:00 on September
               30 in New York, October 1 in UTC), 1007 (137), 1008 (169.50,
               processed September 12, created October 2; its shipping
               16.95 refunded by an import on October 4 with processed_at
               September 20), 1010 (70, customer 3's only order, cancelled
               unpaid on October 2)
    October    1011 (40, free shipping), 1012 (272.50, guest, import duties
               34.20 and their tax 4.45 inside)
1001 also sold a 25 gift card, refunded on August 20, and 1007 took a 12
tip: both are inside the order's total_price and neither is a sale. Cancelled: 1005 and 1010. Customer 1 by processed_at: 1001, 1004, 1008,
1007. Customer 2: 1003, 1005 (cancelled), 1006, 1011. Customer 3: 1010
(cancelled). Guests: 1002, 1012. The input also holds
1004's version before its refund, placed for customer 2, 1008's version
before its shipping was refunded, 1005's version between its cancel and
refund with the same updated_at but an earlier load, and second copies of
1011 and 1006's refund, and a later version of 1004's refund with the same
line; the numbers are those of the latest versions only.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check, questions  # noqa: E402

MODEL = "entities/commerce.yaml"

if __name__ == "__main__":
    windows = sys.argv[1:] == ["--windows"]
    check(MODEL, questions("shopify", windows))
