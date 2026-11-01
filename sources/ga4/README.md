# GA4 package

Maps the [GA4 BigQuery export](https://support.google.com/analytics/answer/7029846)
onto the `web_analytics` entities: `events`, `sessions` and `purchases`.
What the model answers: [docs/web_analytics.md](../../docs/web_analytics.md).
Installing the package in a dbt project, time zones and several
properties: [docs/deployment.md](../../docs/deployment.md).

## Quick start

Try the GA4 package on Google's public sample
[`ga4_obfuscated_sample_ecommerce`](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset):
4.3 million events from November 2020 to January 2021. You need
[ClickHouse](https://clickhouse.com/docs/install), the
[gcloud CLI](https://cloud.google.com/sdk/docs/install),
[uv](https://docs.astral.sh/uv/), dbt v2 (`pip install dbt-oss`) and
[dactopus-ossie-clickhouse](https://github.com/Dactopus/dactopus-ossie-clickhouse) 0.12.0 or
later with its MCP server (`pip install "dactopus-ossie-clickhouse[mcp]"`), and
the dbt profile of the README's [Quick start](../../README.md#quick-start).
Tested on ClickHouse 26.9.

1. **Export.** A Google Cloud project in the
   [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) is
   enough: no billing account, no Cloud Storage bucket. Save the script
   below as `export_ga4.py` and run:

   ```bash
   gcloud auth login
   gcloud projects create <project-id>
   gcloud services enable bigquery.googleapis.com --project <project-id>
   uv run --with google-cloud-bigquery --with google-cloud-bigquery-storage \
       --with pyarrow export_ga4.py <project-id> data/ga4
   ```

   The script reads the daily tables with the BigQuery Storage Read API
   and writes one Parquet file per day (about 200 MB, 10 minutes). It
   passes the gcloud login token explicitly, so a
   `GOOGLE_APPLICATION_CREDENTIALS` set for another project does not get
   in the way:

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

2. **Load** into the package's input table
   [`sources/ga4/input.sql`](input.sql). It declares only the
   columns the package reads; any other way of delivering the export must
   fill the same table. Its database is a parameter, `ga4_raw` here; the
   package reads another one from the dbt variable `ga4_input_database`.

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

   The sample is older than the `session_traffic_source_last_click`
   column. Exports from October 2024 on have it with the
   `cross_channel_campaign` record the package reads: load it too, adding
   the column to the `INSERT` list and this expression to the `SELECT`.
   Without it the package falls back to the first source seen in a
   session, and revenue by source will not match the GA4 interface.

   ```sql
   tuple(tuple(session_traffic_source_last_click.cross_channel_campaign.source,
               session_traffic_source_last_click.cross_channel_campaign.medium,
               session_traffic_source_last_click.cross_channel_campaign.campaign_name))
     AS session_traffic_source_last_click
   ```

3. **Build** the canonical tables, with the profile of the README's [Quick start](../../README.md#quick-start).

   ```bash
   dbt build --project-dir sources/ga4
   ```

4. **Validate** the model against the built tables. The model names its
   tables without a database: dactopus-ossie-clickhouse reads them in the database
   of its URL.

   ```bash
   dactopus-ossie-clickhouse validate entities/web_analytics.yaml --url http://user:password@host:8123/dactopus
   ```

5. **Ask.** Serve the model to an AI agent over MCP with
   `dactopus-ossie-clickhouse serve entities/web_analytics.yaml --url ...`, the
   same URL; its [README](https://github.com/Dactopus/dactopus-ossie-clickhouse#readme)
   shows how to connect an agent. Try sessions, conversion rate and
   revenue, by traffic source, device, country and date. The sample's
   dates are in UTC, the default, so the command takes no time zone; an
   export of your own property takes the property's ([docs/deployment.md](../../docs/deployment.md)).


## Known differences from the GA4 interface

Numbers from the model and from the GA4 interface can differ for reasons
the model states in its descriptions:

- **Sessions and users** are counted exactly; the GA4 interface estimates
  them, so they differ slightly. A user is a browser on a device
  (`user_pseudo_id`), not a person.
- **Traffic source** matches the interface (last non-direct click) only
  for exports from October 2024 on, loaded with the
  `session_traffic_source_last_click` column. Older exports fall back to
  the first source seen in the session.
- **Purchases** are what the site sent to GA4, not the store's orders:
  purchases made with tracking blocked are missing. A purchase sent twice
  by the same user with the same transaction id counts once, as in GA4.
- **Revenue** is in the currency of each purchase. A store that sells in
  several currencies has to read it by `purchases.currency`;
  `purchases.gross_purchase_revenue_usd` is converted by Google at a
  rate it does not document.
- **Refunds** are not subtracted: the model reads purchase events only.
  The metrics are GA4's gross purchase revenue; the interface's
  "Purchase revenue" subtracts the refunds the site sent to GA4, so it
  is lower when there were any ([GA4 metrics](https://support.google.com/analytics/answer/9143382)).
- **Dates** are in the GA4 property's time zone; a session that crosses
  midnight counts once, on the day it started. "Today" is the
  property's date when the model is served in that zone ([docs/deployment.md](../../docs/deployment.md)). Properties outside UTC
  are not tested yet ([#1](https://github.com/Dactopus/dactopus-data-models/issues/1)).
