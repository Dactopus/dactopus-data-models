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

The GA4 package builds the tables the model reads; where its numbers
differ from the GA4 interface, and why:
[Known differences from the GA4 interface](../sources/ga4/README.md#known-differences-from-the-ga4-interface).
Time zones, several properties and installing the package:
[deployment.md](deployment.md).
