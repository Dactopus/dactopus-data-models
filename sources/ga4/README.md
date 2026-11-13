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
       --with pyarrow export_ga4.py <project-id> data/ga4
   ```

   It writes the daily tables to Parquet via the BigQuery Storage Read
   API (about 200 MB, 10 minutes) with the gcloud login token, so another
   project's `GOOGLE_APPLICATION_CREDENTIALS` does not interfere:

   ```python
   import pathlib, subprocess, sys
   import pyarrow.parquet as pq
   from google.cloud import bigquery
   from google.oauth2.credentials import Credentials

   project, out = sys.argv[1], pathlib.Path(sys.argv[2])
   out.mkdir(parents=True, exist_ok=True)
   token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
   client = bigquery.Client(project=project, credentials=Credentials(token))
   dataset = "bigquery-public-data.ga4_obfuscated_sample_ecommerce"
   for table in client.list_tables(dataset):
       path = out / f"{table.table_id}.parquet"
       if not path.exists():
           rows = client.list_rows(client.get_table(table)).to_arrow(create_bqstorage_client=True)
           pq.write_table(rows, path, compression="zstd")
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
