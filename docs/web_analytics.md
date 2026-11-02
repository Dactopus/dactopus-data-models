# The web_analytics model

[`entities/web_analytics.yaml`](../entities/web_analytics.yaml) has 12
metrics, each on the dataset whose rows it counts; a question names one
as `dataset.metric` (`sessions.session_count`):

- sessions: `session_count`, `engaged_sessions`, `engagement_rate`,
  `users`, `session_conversion_rate`, `user_conversion_rate`,
  `page_view_count`. They break down by the session's date, week and
  month; traffic source, medium and campaign; landing page, device and
  country.
- purchases: `purchase_count`, `gross_purchase_revenue`,
  `gross_purchase_revenue_usd`, `average_gross_purchase_revenue`. They
  break down by the session fields above, and by the purchase's own
  date, week, month and currency.
- events: `event_count`. It breaks down by the session fields above, and
  by the event's own date, name, page, device and country.

The descriptions in the file say what each one counts.

Over the tables of several GA4 properties (a union), every dataset has
the field `source_id`, the property's label. A user is a browser within
its property: a browser that visited two properties counts in each, so
`sessions.users` adds up across them, and the model cannot say how many
browsers visited both. Dates are in each property's own time zone.

GA4 exports a day to BigQuery after the day is over: the daily table
usually arrives in the afternoon of the following day in the property's
time zone, sometimes later, and takes events that arrive late for two
more calendar days, so it can change until three days after its date
([Google's
documentation](https://support.google.com/analytics/answer/9358801)).
The package's loading recipe reads the daily tables, so the latest date
with rows is a whole day, and the days after it have no rows until their
tables arrive. The model's instructions tell an agent to say up to which
date the data reaches, and not to report the days after it as days
without visits.

The GA4 package builds the tables the model reads; where its numbers
differ from the GA4 interface, and why:
[Known differences from the GA4 interface](../sources/ga4/README.md#known-differences-from-the-ga4-interface).
Time zones, several properties and installing the package:
[deployment.md](deployment.md).
