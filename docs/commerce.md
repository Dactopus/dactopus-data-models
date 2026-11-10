# The commerce model

[`entities/commerce.yaml`](../entities/commerce.yaml) has 49 metrics. Each
is on the dataset whose rows it counts, and a question names it as
`dataset.metric` (`orders.revenue`):

- orders: `order_count`, `all_orders`, `all_orders_total`, `revenue`,
  `refunded_amount`, `refund_rate`, `average_order_value`,
  `items_per_order`, `discount_amount`, `shipping_amount`, `tax_amount`,
  `buyer_count`, `repeat_order_share`, `average_days_between_orders`.
  They break down by the order's date, week, month and day of the
  week; payment and
  fulfillment status, cancelled or not, counted in the store's reports
  or not, channel, currency and the store's platform; shipping country,
  region and city; new or repeat customer, the order's place among its customer's orders,
  days since the customer's previous order and months since their
  first; and by the customer's fields below, such as the month of their
  first order (the cohort).
- customers: `customers.customer_count`, `net_amount`,
  `average_customer_value`, and the share of customers who ordered a
  second time within 30, 60, 90 or 365 days of their first order,
  `second_order_rate_30_days` to `second_order_rate_365_days`, counted
  among the customers whose window is over. They break down by the
  customer's first and last order date, cohort month and number of
  orders. A customer is one the store's report of new and returning
  customers counts: at Shopify the store's customer record, at
  WooCommerce an account or a guest by billing email.
- order lines (`order_lines`): `items_sold`, `items_net`, `line_revenue`,
  `items_returned`, `line_returned_amount`, `line_net_revenue`. They
  break down by product, variant, SKU and title, by the order fields
  above, and by the catalog's fields below, such as the product's status
  now; a line of a product no longer in the catalog has none. Returns
  count on the date of the order.
- categories (`line_categories`): `category_items_sold`, `category_revenue`,
  `category_items_returned`, `category_returned_amount`,
  `category_net_revenue`, and the same five over a category with its
  subcategories, `category_tree_items_sold` to
  `category_tree_net_revenue`. They break down by
  `line_categories.category` and `category_path`, and by the order fields
  above.
- brands (`line_brands`): `brand_items_sold`, `brand_revenue`,
  `brand_items_returned`, `brand_returned_amount`, `brand_net_revenue`.
  They break down by `line_brands.brand` and by the order fields above.
- discount codes (`order_discount_codes`): `code_order_count`,
  `code_revenue`, `code_discount_amount`, `code_buyer_count`,
  `code_count`. They break down by
  `order_discount_codes.discount_code` and by the order fields above. An
  order with two codes counts whole under each, and its discount is not
  split between them; a discount the store applies without a code is no
  code.
- refunds (`refunds`): `refund_count`, `refunds_total`. They break
  down by the refund's own date, week and month, and by the order fields
  above.
- sales events: `net_revenue`. It breaks down by the event's date, week,
  month and kind (an order, a refund, a cancellation), and by the order
  fields above.
- the catalog: `products.product_count`, by status (active, draft,
  archived), title and the date of the last sale;
  `product_categories.product_count` by category,
  `product_categories.category_tree_product_count` for a category with
  its subcategories, and `product_brands.product_count` by brand.

A category is the product type at Shopify and a product category at
WooCommerce, where categories nest; a brand is the vendor at Shopify and
a product brand at WooCommerce. Both are the product's current ones: a
product moved to another category takes its past sales with it, as in
the stores' reports. A line counts in every category and brand of its
product, so they overlap and never add up to a total. The category
metrics count a line in its product's own categories, as WooCommerce
Analytics' Categories report does; the category tree metrics
(`category_tree_revenue` and the others) count it in the categories above
them too, so filtered by one category (`line_categories.category_path`)
they give that category with its subcategories, each line once.
Collections and tags are not modelled.

The numbers follow the store's own reports, each dataset its own. The
metrics of orders and of what is built from them (order lines,
categories, brands, refunds, sales events) count only the orders the
store's sales reports count (`orders.in_sales_reports`), but
`orders.all_orders` and `orders.all_orders_total`. Shopify's reports
count every order; WooCommerce's, by default, paid orders that are not
cancelled or failed. Customers follow the store's report of new and
returning customers, which at WooCommerce counts an order on hold that is
not paid yet: the metrics of `customers` count it, the sales metrics do
not, and the dataset's description says so.

"Sales" or "revenue" without a qualifier is `sales_events.net_revenue`:
orders less refunds and cancellations, with shipping and tax. By
`sales_events.event_month` it gives each month's sales as the store's
reports show them, a refund or a cancellation in the month it was made;
by `orders.order_month`, what each month's orders earned, later refunds
included. `orders.revenue` is orders as placed. Amounts are in the
store's currency.

Dates are in the store's time zone, and so is "today" (`CURRENT_DATE`)
when the model is served in that zone ([deployment.md](deployment.md)).

Over the tables of several stores (a union), every dataset has the
field `source_id`, the store's label, and `orders.platform` says whether
a store is `shopify` or `woocommerce`. An order, customer or product id
is unique within its store only, so a question groups or filters by one
together with `source_id`. Counts add up across stores; amounts are in each
store's currency (`orders.currency`) and the model converts none, so the
instructions have an agent give each currency apart and never add up,
rank or compare amounts in two. A customer of two stores counts in each.

The Shopify and WooCommerce packages build the tables the model reads;
where their numbers differ from the stores' own reports, and why:
[Known differences from Shopify's reports](../sources/shopify/README.md#known-differences-from-shopifys-reports)
and [Known differences from WooCommerce Analytics](../sources/woocommerce/README.md#known-differences-from-woocommerce-analytics).
Time zones, several stores and installing the packages:
[deployment.md](deployment.md).
