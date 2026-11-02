"""Ask the commerce model questions over tests/woocommerce/fixture.sql and
compare the answers with numbers derived by hand from those rows.

Run from the repository root after loading the input tables and the fixture
into one database (the query parameter db) and building the WooCommerce
package over it in the store's time zone, America/New_York:

    clickhouse client --param_db=woocommerce_input --multiquery < sources/woocommerce/input.sql
    clickhouse client --param_db=woocommerce_input --multiquery < tests/woocommerce/fixture.sql
    dbt build --project-dir sources/woocommerce --profiles-dir tests \
        --vars '{woocommerce_input_database: woocommerce_input, woocommerce_timezone: America/New_York, woocommerce_currency: USD}'
    OSSIE_CLICKHOUSE_TIME_ZONE=America/New_York uv run tests/woocommerce/check_numbers.py

$OSSIE_CLICKHOUSE_URL is the ClickHouse URL with the package's target
database, e.g. http://127.0.0.1:8123/dactopus. The model is asked in the
zone it was built in, $OSSIE_CLICKHOUSE_TIME_ZONE.

With --windows it asks about the retention windows instead
(window_cases), over tests/woocommerce/fixture.sql and
tests/woocommerce/windows.sql synced into a database of their own, with no
row synced later.

The questions, the numbers they must answer and how each is derived are in
tests/woocommerce/questions.yaml.

The numbers are those of the store's reports with WooCommerce's default
settings: an order is dated by its payment and counted unless it is
pending, cancelled or failed; an order not yet paid is not counted. Orders
of the fixture (fixture.sql lists them):
    counted      101 (88), 103 (33), 104 (70.40, refunded 29.70), 109 (30.80),
                 110 (46), 111 (33, refunded 33), 112 (66, refunded 5),
                 113 (16.50), 117 (66 USD, 59.40 EUR): 9 orders, 449.70
    not counted  102 on hold (no payment date), 106 pending, 107 cancelled
                 (refund 904 of 22 on September 10 left out with it), 108
                 failed, 118 and 119 on hold: rows of orders all the same
    not orders   114 in the trash, 115 a checkout draft, 116 deleted
By month of payment in New York: August 101, 103 (paid at 22:10 on August
31, September 1 in UTC); September 104 (placed August 30), 109, 110, 111;
October 112, 113 (paid on delivery October 6, placed October 3), 117.
Refunds of counted orders: 902 (111, 33) September 22, 903 (112, 5) October
2, 901 (104, 29.70) October 5.
Customer 1 by date placed: 101, 104, 109, 111, 117. Customer 2: 102 (a
guest's, billed to customer 2's email), 103, 107 (cancelled, not
numbered), 110, 113. Guest4, customer -112: 118, 112. Customer -119: 119, a
guest's without an email. 106 and 108, guests' too, are not counted.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ask_model import check, questions  # noqa: E402

MODEL = "entities/commerce.yaml"

if __name__ == "__main__":
    windows = sys.argv[1:] == ["--windows"]
    check(MODEL, questions("woocommerce", windows))
