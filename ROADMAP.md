# Roadmap

Where the project is heading. The [README](README.md) describes what works
today; plans live here. There are no dates: an item moves when it is
ready. An item's decisions are recorded in its pull request and the
changelog; questions it leaves open become issues. This file changes
through pull requests, like the code.

- **Next**: the next piece of work.
- **Needs contributors**: useful, waiting for someone with the data or
  the time.
- **Later**: planned, after what is next.
- **Exploring**: worth doing; scope or demand is still open.
- **Not planned**: see [Out of scope](CONTRIBUTING.md#out-of-scope) in
  CONTRIBUTING.md.

## Next

Nothing yet.

## Needs contributors

### Check the GA4 package on a recent export

[#1](https://github.com/Dactopus/dactopus-data-models/issues/1). The
traffic source from `session_traffic_source_last_click` is tested only on
hand-written rows, and properties outside UTC are not tested at all.

## Later

### What each discount code took off

`order_discount_codes` gives each code the whole discount of its orders.
A code's own amount needs the order's discount applications at Shopify,
a new input column, and the coupon item's `discount_amount` at
WooCommerce.

### Payment method

How customers paid, as Shopify's report of payments and WooCommerce's
order fields give it. Shopify's report counts transactions: each payment
and each refund on its own date, and an order paid with a gift card and
a card under both. Its input needs the order's
transactions. WooCommerce keeps one payment method on each order, a
column its input would add.

### Advertising: Google Ads and Meta Ads

Spend, impressions and clicks by date and campaign. With two sources from
the start, the canonical fields can be chosen right away; Fivetran's
[dbt_ad_reporting](https://github.com/fivetran/dbt_ad_reporting) already
shows a common schema across eleven ad platforms. A brand buys ads on
several platforms at once, so one deployment will need more than one
package writing the same entity. That changes a layout rule in
CONTRIBUTING.md, which has a deployment pick one package per entity.

## Exploring

### GA4 items: product views and the funnel

GA4 e-commerce events carry their items: id, name, up to five category
levels, price and quantity. Revenue by product and category comes from
the store packages; GA4 items would add what only the site sees: product
views, additions to the cart and a funnel per product. In the public
sample export, viewed and purchased items carry different ids, so a
funnel needs a property that tags them alike. It adds a column to the
package's input, a breaking change.

### IoT: local time

The `iot` domain dates every reading in UTC: the source gives a site no
time zone. A site's time zone from its coordinates would answer "by day"
in local days, which matters in a country with several zones.

### IoT: `devices_archive` built incrementally

`devices_archive`, the table behind the view `devices`, is rebuilt whole
on every run and reads every reading, so its build time grows with the
history (0.05 seconds for a month of Australia). An incremental model
would read only the sensor-days a run loads; the input and the numbers
stay the same.

### Stream as a dimension

A GA4 property can have a website stream and app streams. The package
counts them together, as the GA4 interface does; a stream dimension would
compare the website with the apps. It adds input columns too.

### Magento (Adobe Commerce)

Magento Open Source and Adobe Commerce share one code base and run
about three times as many live stores as BigCommerce, though the count
has been falling since 2021 ([Store
Leads](https://storeleads.app/reports/magento),
[BigCommerce](https://storeleads.app/reports/bigcommerce)). A store
keeps its data in its own MySQL database, which reaches ClickHouse by
change data capture (CDC), as a WooCommerce store's does
([sources/woocommerce](sources/woocommerce/README.md)). Open: whether
Magento's order tables, copied this way, give the numbers of Magento's
own reports; and demand, since the stores the library is built for today
run Shopify or WooCommerce.
