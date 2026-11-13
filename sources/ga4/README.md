# GA4 package

Maps the [GA4 BigQuery export](https://support.google.com/analytics/answer/7029846)
onto the `web_analytics` entities `events`, `sessions` and `purchases`.
What the model answers: [docs/web_analytics.md](../../docs/web_analytics.md).
Installing the package in a dbt project, time zones and several
properties: [docs/deployment.md](../../docs/deployment.md).

## Quick start

Try the package on Google's public sample
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset):
4.3 million events, November 2020 to January 2021. You need ClickHouse,
dbt with the profile and dactopus-ossie-clickhouse from the README's
[Quick start](../../README.md#quick-start), plus the
[gcloud CLI](https://cloud.google.com/sdk/docs/install) and
[uv](https://docs.astral.sh/uv/) for the export.

1. **Export.** A Google Cloud project in the
   [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) is
   enough, without billing or a Cloud Storage bucket. Save the script
   below as `export_ga4.py` and run:

   ```bash
   gcloud auth login
   gcloud projects create <project-id>
   gcloud services enable bigquery.googleapis.com --project <project-id>
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> \
       bigquery-public-data.ga4_obfuscated_sample_ecommerce data/ga4
   ```

   It writes each daily table `events_YYYYMMDD` of the dataset to
   Parquet via the BigQuery Storage Read API (about 200 MB, 10 minutes)
   with the gcloud login token, so another project's
   `GOOGLE_APPLICATION_CREDENTIALS` does not interfere. A fourth
   argument, a date as `YYYYMMDD`, limits it to the tables from that
   date on ([Your property](#your-property)):

   ```python
   import pathlib, re, subprocess, sys
   import pyarrow.parquet as pq
   from google.cloud import bigquery
   from google.oauth2.credentials import Credentials

   project, dataset, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
   since = sys.argv[4] if len(sys.argv) > 4 else "00000000"
   out.mkdir(parents=True, exist_ok=True)
   token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
   client = bigquery.Client(project=project, credentials=Credentials(token))
   for table in client.list_tables(dataset):
       day = re.fullmatch(r"events_(\d{8})", table.table_id)
       if day and day[1] >= since:
           rows = client.list_rows(client.get_table(table)).to_arrow(create_bqstorage_client=True)
           pq.write_table(rows, out / f"{table.table_id}.parquet", compression="zstd")
           print(table.table_id, rows.num_rows)
   ```

2. **Load** into the input table [`sources/ga4/input.sql`](input.sql).
   It holds only the columns the package reads; any other delivery of
   the export fills it too. It has no label; its database and
   the label are dbt variables ([Variables](#variables)).

   ```bash
   clickhouse client --param_db=ga4_raw --multiquery < sources/ga4/input.sql
   clickhouse local --query "
     SELECT event_date, event_timestamp, event_name, event_params,
            user_pseudo_id, user_id,
            tuple(device.category) AS device, tuple(geo.country) AS geo,
            tuple(ecommerce.purchase_revenue, ecommerce.purchase_revenue_in_usd,
                  ecommerce.tax_value,
                  ecommerce.shipping_value, ecommerce.transaction_id) AS ecommerce
     FROM file('data/ga4/*.parquet') FORMAT Native" |
   clickhouse client --query "
     INSERT INTO ga4_raw.events (event_date, event_timestamp, event_name,
       event_params, user_pseudo_id, user_id, device, geo, ecommerce)
     FORMAT Native"
   ```

   Exports from October 2024 on, unlike the sample, have
   `session_traffic_source_last_click`, whose `cross_channel_campaign`
   the package reads: add the column to the `INSERT` and this expression
   to the `SELECT`:

   ```sql
   tuple(tuple(session_traffic_source_last_click.cross_channel_campaign.source,
               session_traffic_source_last_click.cross_channel_campaign.medium,
               session_traffic_source_last_click.cross_channel_campaign.campaign_name))
     AS session_traffic_source_last_click
   ```

   This loads the sample once. A property's export arrives day by day
   and loads as [Your property](#your-property) says.

3. **Build** the canonical tables.

   ```bash
   dbt build --project-dir sources/ga4
   ```

4. **Validate and check.** Validate the model against the built tables
   (it names no database: dactopus-ossie-clickhouse reads its URL's).
   Then compare `check_numbers.py`'s answers to 10 questions over the
   hand-written rows of
   [`tests/ga4/fixture.sql`](../../tests/ga4/fixture.sql) with numbers
   worked out by hand.

   ```bash
   dactopus-ossie-clickhouse validate entities/web_analytics.yaml --url http://user:password@host:8123/dactopus
   clickhouse client --param_db=ga4_sample_raw --multiquery < sources/ga4/input.sql
   clickhouse client --param_db=ga4_sample_raw --multiquery < tests/ga4/fixture.sql
   CLICKHOUSE_DATABASE=ga4_sample dbt build --project-dir sources/ga4 \
       --vars '{ga4_input_database: ga4_sample_raw}'
   OSSIE_CLICKHOUSE_URL=http://user:password@host:8123/ga4_sample python3 tests/ga4/check_numbers.py
   ```

5. **Ask.** Serve the model over MCP with
   `dactopus-ossie-clickhouse serve entities/web_analytics.yaml --url ...`
   at the same URL ([connecting an agent](https://github.com/Dactopus/dactopus-ossie-clickhouse#readme)).
   Try sessions, conversion rate and revenue by traffic source, device,
   country and date. The sample is in UTC, the default; serve your own
   export in the property's zone, so "today" is its date
   ([docs/deployment.md](../../docs/deployment.md)).

## Your property

1. **Link** the property to a Google Cloud project with the daily export
   (Admin > Product links > BigQuery links,
   [setup](https://support.google.com/analytics/answer/9823238)). It
   writes a table `events_YYYYMMDD` for each day, in the property's
   time zone, to the dataset `analytics_<property-id>`; the first one
   arrives within a day. The package reads only these: the tables
   `events_intraday_*` of the streaming export have no session source.

2. **Load.** Google updates a day's table for up to 72 hours after its
   date ([export schedule](https://support.google.com/analytics/answer/9358801)),
   so each load exports again the days from three days before the
   latest day loaded and replaces their rows. Loaded a second time
   without the `DELETE`, a day would count its events and page views
   twice. The first load runs the same commands: on an empty input
   `since` is `00000000`, every table.

   ```bash
   clickhouse client --param_db=ga4_raw --multiquery < sources/ga4/input.sql
   since=$(clickhouse client --query "
     SELECT ifNull(formatDateTime(parseDateTimeOrNull(max(event_date), '%Y%m%d')
                                  - INTERVAL 3 DAY, '%Y%m%d'), '00000000')
     FROM ga4_raw.events")
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> \
       <project-id>.analytics_<property-id> data/ga4/$since $since
   clickhouse client --query "CREATE TABLE IF NOT EXISTS ga4_raw.events_load AS ga4_raw.events"
   clickhouse client --query "TRUNCATE TABLE ga4_raw.events_load"
   clickhouse local --query "
     SELECT event_date, event_timestamp, event_name, event_params,
            user_pseudo_id, user_id,
            tuple(device.category) AS device, tuple(geo.country) AS geo,
            tuple(ecommerce.purchase_revenue, ecommerce.purchase_revenue_in_usd,
                  ecommerce.tax_value,
                  ecommerce.shipping_value, ecommerce.transaction_id) AS ecommerce,
            tuple(tuple(session_traffic_source_last_click.cross_channel_campaign.source,
                        session_traffic_source_last_click.cross_channel_campaign.medium,
                        session_traffic_source_last_click.cross_channel_campaign.campaign_name))
              AS session_traffic_source_last_click
     FROM file('data/ga4/$since/*.parquet') FORMAT Native" |
   clickhouse client --query "
     INSERT INTO ga4_raw.events_load (event_date, event_timestamp, event_name,
       event_params, user_pseudo_id, user_id, device, geo, ecommerce,
       session_traffic_source_last_click)
     FORMAT Native"
   clickhouse client --multiquery --query "
     DELETE FROM ga4_raw.events
     WHERE event_date IN (SELECT DISTINCT event_date FROM ga4_raw.events_load);
     INSERT INTO ga4_raw.events SELECT * FROM ga4_raw.events_load"
   ```

   - **The 3** is `ga4_lookback_days` ([Variables](#variables)): change
     both together.
   - **`events_load`** holds a load until it is in ClickHouse whole, and
     the `DELETE` removes only the days it holds. If the export or the
     insert fails, stop there: the input is as it was, and the next load
     exports those days again.
   - **Grants** for the user that loads, on the input database:
     `SELECT`, `INSERT`, `CREATE TABLE`, `TRUNCATE` and `ALTER DELETE`,
     which a `DELETE` needs
     ([DELETE](https://clickhouse.com/docs/sql-reference/statements/delete)).
   - **Tables before October 2024** lack
     `session_traffic_source_last_click.cross_channel_campaign`: load
     them with the expression of [Quick start](#quick-start), step 2.

3. **Build** with `dbt build --project-dir sources/ga4`. The build is
   incremental: it rebuilds the days from `ga4_lookback_days` before the
   latest day it built, which takes in every day the load replaced, and
   a session that starts the day before them. Serve the model in the
   property's time zone ([docs/deployment.md](../../docs/deployment.md)).

## Variables

| Variable | Default | What it sets | Guarded |
| --- | --- | --- | --- |
| `ga4_input_database` | `ga4_raw` | the database of the input table | no |
| `ga4_source_id` | `ga4` | the property's label in every row (`source_id`, [labels](../../docs/deployment.md#labels)) | yes |
| `ga4_lookback_days` | `3` | the days an incremental run rereads before the latest data it has seen | no |

## Changing a setting

The three tables are incremental: a run rebuilds the recent days
([`ga4_lookback_days`](#variables)). A change of a guarded variable
needs `dbt build --full-refresh` once
([docs/deployment.md](../../docs/deployment.md#changing-a-setting)).
The dbt user needs `ALTER MODIFY COMMENT` (part of `ALTER TABLE`) on
them.

## Known differences from the GA4 interface

The model's descriptions state each:

- **Sessions and users** are exact counts; the interface's estimates
  differ slightly.
- **Traffic source** matches the interface (last non-direct click) only
  when loaded with `session_traffic_source_last_click` (step 2); without
  it, the package takes the first source seen in the session.
- **Purchases** are what the site sent, without those made with
  tracking blocked; one sent twice by a user with the same transaction
  id counts once, as in GA4.
- **Revenue** is in each purchase's currency; a store selling in several
  reads it by `purchases.currency`. Google converts
  `purchases.gross_purchase_revenue_usd` at a rate it does not document.
- **Refunds** are not subtracted: the model reads only purchase events,
  GA4's gross purchase revenue. The interface's "Purchase revenue"
  subtracts the refunds the site sent
  ([GA4 metrics](https://support.google.com/analytics/answer/9143382)).
- **Dates** are in the property's time zone; a session that crosses
  midnight counts once, on its first day. Properties outside UTC
  are not tested yet ([#1](https://github.com/Dactopus/dactopus-data-models/issues/1)).
