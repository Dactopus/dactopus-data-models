# Roadmap

Where the project is heading. The [README](README.md) describes what works
today; plans live here. There are no dates: an item moves when it is
ready. Each item gets an issue when work on it starts, and the discussion
happens there. This file changes through pull requests, like the code.

- **Next**: the next piece of work.
- **Needs contributors**: useful, waiting for someone with the data or
  the time.
- **Later**: planned, after what is next.
- **Exploring**: worth doing; scope or demand is still open.
- **Not planned**: see [Out of scope](README.md#out-of-scope) in the
  README.

## Next

### Shopify package and order entities

`orders`, line items and customers, mapped from Shopify. The mapping
logic starts from Fivetran's
[dbt_shopify](https://github.com/fivetran/dbt_shopify) (Apache 2.0); its
staging layer reads Fivetran's connector schema and is rewritten for other
loaders. Canonical fields are chosen on real store data. Until a second
orders source exists, `orders` is provisional.

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

### WooCommerce

The second orders source, which tests that `orders` is not shaped by
Shopify. There is no dbt package to start from. The input is the store's
own order tables ([HPOS](https://developer.woocommerce.com/docs/features/high-performance-order-storage/),
WooCommerce 8.2 and later), and the test data comes from a local test
store, where every expected number is known.

## Exploring

### GA4 items: products and categories

GA4 e-commerce events carry their items: id, name, up to five category
levels, price and quantity. An entity with one row per purchased item
would answer revenue by product or category, which the model cannot
answer today. It adds a column to the package's input, a breaking change.

### Stream as a dimension

A GA4 property can have a website stream and app streams. The package
counts them together, as the GA4 interface does; a stream dimension would
compare the website with the apps. It adds input columns too.
