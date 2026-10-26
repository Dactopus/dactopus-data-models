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
- **Not planned**: see [Out of scope](README.md#out-of-scope) in the
  README.

## Next

### Products: categories, brands and the catalog

The model knows a product only as an order line: revenue and units by
product, variant or SKU, with nothing to group products by. This item
adds, for Shopify and WooCommerce:

- **Category**: the grouping the merchant assigns, the product type in
  Shopify and the product categories in WooCommerce. These are what each
  platform's own reports group by. A WooCommerce product in two
  categories counts in both, as WooCommerce Analytics counts it.
- **Brand**: the vendor in Shopify, the product brand in WooCommerce.
- **Catalog**: every product, sold or not, with the date of its last
  sale.

Category and brand are the product's current ones: moving a product to
another category moves its past sales too, as both platforms' reports
do. The packages read new input (products from Shopify; the term tables
and `wp_posts` from WooCommerce), a breaking change.

## Needs contributors

### Check the GA4 package on a recent export

[#1](https://github.com/Dactopus/dactopus-data-models/issues/1). The
traffic source from `session_traffic_source_last_click` is tested only on
hand-written rows, and properties outside UTC are not tested at all.

## Later

### Advertising: Google Ads and Meta Ads

Spend, impressions and clicks by date and campaign. With two sources from
the start, the canonical fields can be chosen right away; Fivetran's
[dbt_ad_reporting](https://github.com/fivetran/dbt_ad_reporting) already
shows a common schema across eleven ad platforms. A brand buys ads on
several platforms at once, so one deployment will need more than one
package writing the same entity. That changes a layout rule in the
README, which now has a deployment pick one package per entity.

### Customers

A `customers` entity: one row per customer of the store, with their first
and latest order, order count and spend. Today customer counts and new or
repeat orders come from `orders`. The question to settle first is what
identifies a customer: Shopify creates a customer record for a guest
checkout, WooCommerce does not, so the same buyers count differently by
source. Matching customers across systems stays
[out of scope](README.md#out-of-scope).

## Exploring

### GA4 items: product views and the funnel

GA4 e-commerce events carry their items: id, name, up to five category
levels, price and quantity. Revenue by product comes from the store
packages, and by category once Products is done; GA4 items would add
what only the site sees: product views, additions to the cart and a
funnel per product. In the public sample export, viewed and purchased
items carry different ids, so a funnel needs a property that tags them
alike. It adds a column to the package's input, a breaking change.

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
