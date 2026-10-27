{# The current state of the rows of an input table (input.sql): each key's
   latest version, and nothing when that version is a delete. Dropping
   deletes after the sort, not before, keeps a deleted row from coming
   back in its version before the delete. Two copies of one version are
   the same row, but CDC that delivers a batch again stamps the copies
   with their own sync times: the latest is taken, or a model's synced_at,
   and the window of its next run, would depend on which copy a read met
   first. `where` must keep or drop whole keys, so it may only test
   columns that never change for a key, such as an item's order_id. #}
{% macro woocommerce_current(table, key, where='true') -%}
(SELECT * FROM (SELECT * FROM {{ source('woocommerce_raw', table) }} WHERE {{ where }}
                ORDER BY _peerdb_version DESC, _peerdb_synced_at DESC LIMIT 1 BY {{ key }})
 WHERE _peerdb_is_deleted = 0)
{%- endmacro %}

{# A time column: UTC, and NULL when empty. CDC writes an empty MySQL
   datetime as 1970-01-01 00:00:00, or as NULL with PEERDB_NULLABLE on
   (input.sql). Test the raw value: a date of 1970-01-01 in a zone west
   of UTC wraps around to 2149. #}
{% macro woocommerce_time(column) -%}
if(ifNull(toUnixTimestamp64Micro({{ column }}), 0) <= 0, NULL, toTimeZone({{ column }}, 'UTC'))
{%- endmacro %}

{# A list of strings as a ClickHouse array. #}
{% macro woocommerce_strings(values) -%}
CAST([{% for v in values %}'{{ v }}'{% if not loop.last %}, {% endif %}{% endfor %}], 'Array(String)')
{%- endmacro %}

{# The core status an order's status stands for: plugins' statuses through
   woocommerce_order_statuses, core statuses as they are. #}
{% macro woocommerce_core_status(status) -%}
{%- set statuses = var('woocommerce_order_statuses') -%}
{%- if statuses -%}
transform({{ status }}, {{ woocommerce_strings(statuses.keys()) }}, {{ woocommerce_strings(statuses.values()) }}, {{ status }})
{%- else -%}
{{ status }}
{%- endif -%}
{%- endmacro %}

{% macro woocommerce_store_currency() -%}
{%- if not var('woocommerce_currency') -%}
{{ exceptions.raise_compiler_error("Set woocommerce_currency to the store's currency code, such as USD: the input tables do not hold it.") }}
{%- endif -%}
'{{ var("woocommerce_currency") }}'
{%- endmacro %}

{# The orders among the current rows of wc_orders: no refunds, no checkout
   drafts (an order not placed yet), nothing in the trash. The status
   loses its wc- prefix (the trash has none). `where` filters ids. #}
{% macro woocommerce_orders(where='true') -%}
(SELECT
    o.id AS id,
    replaceRegexpOne(ifNull(o.status, ''), '^wc-', '') AS status,
    {{ woocommerce_core_status('status') }} AS core_status,
    ifNull(o.currency, '') AS order_currency,
    ifNull(o.tax_amount, 0) AS tax_amount,
    ifNull(o.total_amount, 0) AS total_amount,
    nullIf(ifNull(o.customer_id, 0), 0) AS customer_id,
    nullIf(ifNull(o.billing_email, ''), '') AS customer_email,
    -- WooCommerce sets it when the order is created: never empty.
    toTimeZone(assumeNotNull(o.date_created_gmt), 'UTC') AS placed_time,
    o._peerdb_synced_at AS synced_at
 FROM {{ woocommerce_current('wc_orders', 'id', where) }} AS o
 WHERE o.type = 'shop_order' AND status NOT IN ('trash', 'auto-draft', 'draft', 'checkout-draft'))
{%- endmacro %}

{# The products among the current rows of posts: post_type product, its
   variations (product_variation) apart, and nothing a new product's
   editor has not saved yet (auto-draft). Products in the trash are
   there: WordPress keeps their terms. #}
{% macro woocommerce_products() -%}
(SELECT ID AS product_id, ifNull(post_title, '') AS title, ifNull(post_status, '') AS status
 FROM {{ woocommerce_current('posts', 'ID', "post_type = 'product'") }}
 WHERE status != 'auto-draft')
{%- endmacro %}

{# The terms of a taxonomy on the products (woocommerce_products): one row
   per product and term, with the term's term_id. A product is linked to
   the term's term_taxonomy_id, which may differ from its term_id. #}
{% macro woocommerce_product_terms(taxonomy) -%}
(SELECT l.object_id AS product_id, t.term_id AS term_id
 FROM {{ woocommerce_current('term_relationships', 'object_id, term_taxonomy_id',
                             'object_id IN (SELECT product_id FROM ' ~ woocommerce_products() ~ ')') }} AS l
 INNER JOIN {{ woocommerce_current('term_taxonomy', 'term_taxonomy_id', "taxonomy = '" ~ taxonomy ~ "'") }} AS t
     ON t.term_taxonomy_id = l.term_taxonomy_id)
{%- endmacro %}

{# The names of the terms in `term_ids`, a subquery. #}
{% macro woocommerce_term_names(term_ids) -%}
(SELECT term_id, ifNull(name, '') AS name FROM {{ woocommerce_current('terms', 'term_id', 'term_id IN ' ~ term_ids) }})
{%- endmacro %}

{# An exchange rate kept in order meta, as a number; NULL unless positive. #}
{% macro woocommerce_rate_value(value) -%}
if(toFloat64OrZero({{ value }}) > 0 AND isFinite(toFloat64OrZero({{ value }})),
   toDecimal256OrNull(toString(toFloat64OrZero({{ value }})), 18), NULL)
{%- endmacro %}

{# How to turn the amounts of each order or refund in `ids` into the store's
   currency: amount * rate_mul / rate_div, NULL when no rate is known.
   An order in the store's currency needs none. An order placed in another
   currency through a multi-currency plugin is converted as the plugin
   converts it for WooCommerce Analytics:
   - WooPayments (includes/multi-currency/Analytics.php,
     update_order_stats_data, https://github.com/Automattic/woocommerce-payments):
     when the order rate (store currency to order currency) is set and the
     order's default currency is the store's, by the rate of the payment
     (order currency to store currency), else by the inverse of the order
     rate.
   - FOX - Currency Switcher Professional for WooCommerce 1.5.5
     (classes/dashboard_stat.php, recalculate_order_stats): divided by
     _woocs_order_rate. Without that meta FOX takes the currency's rate
     from its settings at the time, which the input does not hold: no
     rate here.
   rate_fox: FOX rounds the total by itself; WooPayments rounds the
   amount before shipping and tax, shipping and tax apart and adds them up
   (woocommerce_total). #}
{% macro woocommerce_rates(ids) -%}
{%- set store = woocommerce_store_currency() -%}
(SELECT
    h.id AS order_id,
    ifNull(h.currency, '') AS order_currency,
    {{ woocommerce_rate_value('m.wcpay_stripe') }} AS wcpay_stripe,
    {{ woocommerce_rate_value('m.wcpay_order') }} AS wcpay_order,
    {{ woocommerce_rate_value('m.fox') }} AS fox,
    order_currency != {{ store }} AND toFloat64OrZero(m.wcpay_order) != 0 AND m.wcpay_default = {{ store }} AS by_wcpay,
    multiIf(order_currency = {{ store }}, toDecimal256(1, 18),
            by_wcpay AND wcpay_stripe IS NOT NULL, wcpay_stripe,
            by_wcpay AND wcpay_order IS NOT NULL, toDecimal256(1, 18),
            NOT by_wcpay AND fox IS NOT NULL, toDecimal256(1, 18),
            NULL) AS rate_mul,
    multiIf(order_currency = {{ store }}, toDecimal256(1, 18),
            by_wcpay AND wcpay_stripe IS NOT NULL, toDecimal256(1, 18),
            by_wcpay AND wcpay_order IS NOT NULL, wcpay_order,
            NOT by_wcpay AND fox IS NOT NULL, fox,
            NULL) AS rate_div,
    order_currency != {{ store }} AND NOT by_wcpay AND fox IS NOT NULL AS rate_fox
 FROM {{ woocommerce_current('wc_orders', 'id', 'id IN ' ~ ids) }} AS h
 LEFT JOIN
 (
     SELECT
         order_id,
         ifNull(argMaxIf(ifNull(meta_value, ''), id, meta_key = '_wcpay_multi_currency_stripe_exchange_rate'), '') AS wcpay_stripe,
         ifNull(argMaxIf(ifNull(meta_value, ''), id, meta_key = '_wcpay_multi_currency_order_exchange_rate'), '') AS wcpay_order,
         ifNull(argMaxIf(ifNull(meta_value, ''), id, meta_key = '_wcpay_multi_currency_order_default_currency'), '') AS wcpay_default,
         ifNull(argMaxIf(ifNull(meta_value, ''), id, meta_key = '_woocs_order_rate'), '') AS fox
     FROM {{ woocommerce_current('wc_orders_meta', 'id', "meta_key IN ('_wcpay_multi_currency_stripe_exchange_rate', "
            ~ "'_wcpay_multi_currency_order_exchange_rate', '_wcpay_multi_currency_order_default_currency', "
            ~ "'_woocs_order_rate') AND order_id IN " ~ ids) }}
     GROUP BY order_id
 ) AS m ON m.order_id = h.id)
{%- endmacro %}

{# An amount in the store's currency, by the rates of `rate` (a relation
   with rate_mul and rate_div): as it is in the store's currency, else
   converted and rounded to `decimals`, the store's price decimals unless
   given. #}
{% macro woocommerce_convert(amount, rate='r', decimals=none) -%}
{%- set d = var('woocommerce_price_decimals') if decimals is none else decimals -%}
if({{ rate }}.rate_mul = 1 AND {{ rate }}.rate_div = 1, toDecimal128({{ amount }}, 8),
   toDecimal128(round(toDecimal256({{ amount }}, 8) * {{ rate }}.rate_mul / {{ rate }}.rate_div, {{ d }}), 8))
{%- endmacro %}

{# The total of an order or refund in the store's currency, rounded as the
   plugin that converted it rounds it for Analytics (woocommerce_rates). #}
{% macro woocommerce_total(total, shipping, shipping_tax, tax, rate='r') -%}
if({{ rate }}.rate_fox, {{ woocommerce_convert(total, rate) }},
   {{ woocommerce_convert('(' ~ total ~ ') - (' ~ shipping ~ ') - (' ~ shipping_tax ~ ') - (' ~ tax ~ ')', rate) }}
   + {{ woocommerce_convert(shipping, rate) }} + {{ woocommerce_convert('(' ~ shipping_tax ~ ') + (' ~ tax ~ ')', rate) }})
{%- endmacro %}

{# Where an incremental run's window starts: the latest sync the model has
   read minus the lookback. A model takes it from the synced_at of its
   rows. With `in_comment`, it takes it from its table's comment, written
   by woocommerce_reading and woocommerce_read, and from its rows while the
   comment has none. An empty model rereads everything: its max() is
   1970-01-01, and DateTime64 goes below it without wrapping. #}
{% macro woocommerce_window_start(in_comment=false) -%}
{%- if in_comment -%}
(coalesce((SELECT toDateTime64OrNull(extract(comment, '^read through ([^;]+) UTC'), 9, 'UTC') FROM system.tables
           WHERE database = '{{ this.schema }}' AND name = '{{ this.identifier }}'),
          (SELECT toTimeZone(max(synced_at), 'UTC') FROM {{ this }}))
 - INTERVAL {{ var('woocommerce_lookback_days') }} DAY)
{%- else -%}
(SELECT max(synced_at) - INTERVAL {{ var('woocommerce_lookback_days') }} DAY FROM {{ this }})
{%- endif -%}
{%- endmacro %}

{# The sync position a model keeps in its table's comment, when its rows
   cannot keep it: refunds has no row for an order without refunds, so
   its latest synced_at is that of the store's last refund, not of its
   last run, and the window would reach back to that refund (#18).
   Pre-hook woocommerce_reading, before the run reads: the comment gets
   the latest sync of wc_orders as the position the run is reading
   through. Post-hook woocommerce_read, after it succeeds: that becomes
   the position read through, where the next window starts; a run that
   fails leaves the previous one. A row synced before that position but
   committed after the run read is caught by the lookback, as in a model
   that keeps the position in its rows. A full refresh creates the table
   anew, without a comment. The comment is only ever
   "read through <time> UTC", "reading through <time> UTC" or both,
   separated by "; ". #}
{% macro woocommerce_comment_position(field) -%}
{%- set r = run_query("SELECT extract(comment, '(?:^|; )" ~ field ~ " through ([^;]+) UTC') FROM system.tables WHERE database = '"
                      ~ this.schema ~ "' AND name = '" ~ this.identifier ~ "'") -%}
{{- return(r.columns[0].values()[0] if r.columns[0].values() else '') -}}
{%- endmacro %}

{% macro woocommerce_reading() -%}
{%- if execute and is_incremental() -%}
{%- set through = woocommerce_comment_position('read') -%}
{%- set latest = run_query("SELECT toString(toTimeZone(max(_peerdb_synced_at), 'UTC')) FROM "
                           ~ source('woocommerce_raw', 'wc_orders')).columns[0].values()[0] -%}
ALTER TABLE {{ this }} MODIFY COMMENT '{% if through %}read through {{ through }} UTC; {% endif %}reading through {{ latest }} UTC'
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}

{% macro woocommerce_read() -%}
{%- set reading = woocommerce_comment_position('reading') if execute and is_incremental() else '' -%}
{%- if reading -%}
ALTER TABLE {{ this }} MODIFY COMMENT 'read through {{ reading }} UTC'
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}

{# Orders with a row of theirs synced since an incremental run's window
   start (woocommerce_window_start). Any of the order's rows counts: the
   order, its operational data, addresses, meta, items and item meta, and
   those of its refunds, which map to their order. With `products`, also
   orders with a line of a product whose lookup row was synced: the
   line's SKU is the product's current one. #}
{% macro woocommerce_changed_orders(products=false, in_comment=false) -%}
{%- set since = "_peerdb_synced_at >= " ~ woocommerce_window_start(in_comment) -%}
(SELECT if(type = 'shop_order_refund', parent_order_id, id) AS order_id FROM {{ source('woocommerce_raw', 'wc_orders') }}
 WHERE id IN (
     SELECT id FROM {{ source('woocommerce_raw', 'wc_orders') }} WHERE {{ since }}
     UNION ALL SELECT order_id FROM {{ source('woocommerce_raw', 'wc_order_operational_data') }} WHERE {{ since }}
     UNION ALL SELECT order_id FROM {{ source('woocommerce_raw', 'wc_order_addresses') }} WHERE {{ since }}
     UNION ALL SELECT order_id FROM {{ source('woocommerce_raw', 'wc_orders_meta') }} WHERE {{ since }}
     UNION ALL SELECT order_id FROM {{ source('woocommerce_raw', 'woocommerce_order_items') }}
     WHERE {{ since }} OR order_item_id IN (
         SELECT order_item_id FROM {{ source('woocommerce_raw', 'woocommerce_order_itemmeta') }}
         WHERE {{ since }}
         {%- if products %}
            OR meta_key IN ('_product_id', '_variation_id') AND meta_value IN (
                SELECT toString(product_id) FROM {{ source('woocommerce_raw', 'wc_product_meta_lookup') }} WHERE {{ since }})
         {%- endif %})))
{%- endmacro %}

{# Pre-hook of an incremental run: remove the rows of the orders it will
   reread. An order deleted, moved to the trash or left without lines or
   refunds is not in the new rows, and delete+insert replaces only the
   orders that are. #}
{% macro woocommerce_delete_changed(products=false, in_comment=false) -%}
{%- if is_incremental() -%}
DELETE FROM {{ this }} WHERE order_id IN {{ woocommerce_changed_orders(products, in_comment) }}
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}

{# The orders an incremental run of orders.sql rereads, kept apart for the
   run: woocommerce_keep_changed fills it before anything is deleted,
   woocommerce_delete_removed and the model read it, and
   woocommerce_drop_changed drops it after the run. Each row is an order
   changed in the window (woocommerce_changed_orders) and the customer the
   model's row of that order names, NULL without one. An order moved to
   another customer renumbers that customer's orders, and an input that
   collapses old versions may have lost the version that named them; the
   model's row is then the only place left that names them, and an order
   that is no longer an order loses that row before the model runs (#17).
   Reading the changed orders once here also spares the hook and the model
   reading them again. A run that fails may have deleted rows the table
   names, so the next run keeps its rows along with its own. #}
{% macro woocommerce_changed_table() -%}
{{ this.incorporate(path={"identifier": this.identifier ~ "__changed"}) }}
{%- endmacro %}

{% macro woocommerce_keep_changed() -%}
{%- if is_incremental() -%}
{%- set left = execute and run_query("EXISTS TABLE " ~ woocommerce_changed_table()).columns[0].values()[0] -%}
CREATE OR REPLACE TABLE {{ woocommerce_changed_table() }} ENGINE = MergeTree ORDER BY tuple() AS
WITH changed AS MATERIALIZED {{ woocommerce_changed_orders() }}
SELECT DISTINCT order_id, previous_customer_id FROM (
    SELECT c.order_id AS order_id, p.customer_id AS previous_customer_id
    FROM changed AS c
    LEFT JOIN (SELECT order_id, customer_id FROM {{ this }} WHERE order_id IN changed) AS p ON p.order_id = c.order_id
    {%- if left %}
    UNION ALL
    SELECT order_id, previous_customer_id FROM {{ woocommerce_changed_table() }}
    {%- endif %})
{{ woocommerce_query_settings() }}
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}

{# Pre-hook after woocommerce_keep_changed: remove the rows of the changed
   orders that are no longer orders (woocommerce_delete_changed). The
   others stay: delete+insert replaces them. #}
{% macro woocommerce_delete_removed() -%}
{%- if is_incremental() -%}
{%- set changed = "(SELECT order_id FROM " ~ woocommerce_changed_table() ~ ")" -%}
DELETE FROM {{ this }} WHERE order_id IN {{ changed }}
AND order_id NOT IN (SELECT id FROM {{ woocommerce_orders('id IN ' ~ changed) }})
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}

{% macro woocommerce_drop_changed() -%}
DROP TABLE IF EXISTS {{ woocommerce_changed_table() }}
{%- endmacro %}

{# Ends each model's query. A CTE marked MATERIALIZED runs once, and its
   references read the result; ClickHouse otherwise runs a CTE again at
   every reference. The changed orders' subquery, referenced through
   several CTEs, made order_lines read 123 million rows for a window of
   two orders out of 320,000 (#18). Needs ClickHouse 26.7 or later:
   26.3, where MATERIALIZED came in, to 26.6 fail on these models with
   errors of their own.
   join_use_nulls = 0: a LEFT JOIN without a match fills the joined
   columns with their type's default, 0 for an amount, which the models
   count on (an order without a refund or a shipping line); a server or
   profile that sets 1 would make them NULL. #}
{% macro woocommerce_query_settings() -%}
SETTINGS enable_materialized_cte = 1, join_use_nulls = 0
{%- endmacro %}
