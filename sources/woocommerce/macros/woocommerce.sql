{# The current state of the rows of an input table (input.sql): each key's
   latest version, and nothing when that version is a delete. Dropping
   deletes after the sort, not before, keeps a deleted row from coming
   back in its version before the delete. Two copies of one version are
   the same row. `where` must keep or drop whole keys, so it may only test
   columns that never change for a key, such as an item's order_id. #}
{% macro woocommerce_current(table, key, where='true') -%}
(SELECT * FROM (SELECT * FROM {{ source('woocommerce_raw', table) }} WHERE {{ where }}
                ORDER BY _peerdb_version DESC LIMIT 1 BY {{ key }})
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

{# Orders with a row of theirs synced since an incremental run's window
   start: the latest sync this model has seen minus the lookback. Any of
   the order's rows counts: the order, its operational data, addresses,
   meta, items and item meta, and those of its refunds, which map to their
   order. With `products`, also orders with a line of a product whose
   lookup row was synced: the line's SKU is the product's current one. An
   empty model rereads everything: its max() is 1970-01-01, and
   DateTime64 goes below it without wrapping. #}
{% macro woocommerce_changed_orders(products=false) -%}
{%- set since = "_peerdb_synced_at >= (SELECT max(synced_at) - INTERVAL " ~ var('woocommerce_lookback_days')
               ~ " DAY FROM " ~ this ~ ")" -%}
(SELECT if(type = 'shop_order_refund', parent_order_id, id) FROM {{ source('woocommerce_raw', 'wc_orders') }}
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
   orders that are. With `removed_only`, only the orders that are no
   longer orders go: orders.sql reads the previous customer of the others
   from this table. #}
{% macro woocommerce_delete_changed(products=false, removed_only=false) -%}
{%- if is_incremental() -%}
{%- set changed = woocommerce_changed_orders(products) -%}
DELETE FROM {{ this }} WHERE order_id IN {{ changed }}
{%- if removed_only %} AND order_id NOT IN (SELECT id FROM {{ woocommerce_orders('id IN ' ~ changed) }}){% endif %}
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}
