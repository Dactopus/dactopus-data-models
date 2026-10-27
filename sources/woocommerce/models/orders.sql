{{ config(unique_key='order_id', order_by='(order_date, order_id)',
          pre_hook=["{{ woocommerce_keep_changed() }}", "{{ woocommerce_delete_removed() }}"],
          post_hook="{{ woocommerce_drop_changed() }}") }}
-- One row per order, in its current state (input.sql). The numbers follow
-- the store's own reports, WooCommerce Analytics, under the settings the
-- package's variables repeat (dbt_project.yml): which date an order is
-- reported by, which statuses the reports leave out.
-- WooCommerce sources: the order tables
-- (https://github.com/woocommerce/woocommerce/blob/trunk/plugins/woocommerce/src/Internal/DataStores/Orders/OrdersTableDataStore.php),
-- statuses (https://woocommerce.com/document/managing-orders/order-statuses/),
-- Analytics settings (https://woocommerce.com/document/woocommerce-analytics/).
{% set report_times = {'date_created': 'o.placed_time', 'date_paid': 'op.paid_time', 'date_completed': 'op.completed_time'} %}
{% if var('woocommerce_date_type') not in report_times %}
{{ exceptions.raise_compiler_error("woocommerce_date_type must be date_paid, date_created or date_completed") }}
{% endif %}
{% set report_time = report_times[var('woocommerce_date_type')] %}
{% set excluded = woocommerce_strings(var('woocommerce_excluded_statuses')) %}
{% set number_key = var('woocommerce_order_number_meta_key') %}
{% set core_statuses = "('pending', 'on-hold', 'processing', 'completed', 'cancelled', 'refunded', 'failed')" %}
WITH
-- Every order, for its customer and the customer's order sequence. The
-- customer is the one WooCommerce Analytics counts
-- (src/Admin/API/Reports/Customers/DataStore.php, get_existing_customer_id_from_order,
-- get_customer_id_by_email, get_or_create_customer_from_order): the
-- account of a registered order; for a guest's, the account that has an
-- order billed to the same email, in any case, the smallest such account
-- where there are several; else the guest, one per email, numbered by the
-- smallest id of their orders, negative so as not to meet an account; and
-- a guest's order without an email is a customer of its own, as Analytics
-- makes it. Analytics keeps its own table of customers; the package reads
-- only the orders (no account's own email, and a guest is joined to an
-- account whatever the order of the two), so the README lists where the
-- two differ.
identified AS MATERIALIZED (
    SELECT
        * REPLACE (coalesce(toInt64(customer_id),
                            if(email_key = '', -toInt64(id), coalesce(toInt64(account_id), -toInt64(guest_id)))) AS customer_id),
        has({{ excluded }}, status) AS excluded
    FROM
    (
        SELECT
            *,
            lowerUTF8(trimBoth(ifNull(customer_email, ''))) AS email_key,
            min(customer_id) OVER (PARTITION BY email_key) AS account_id,
            minIf(id, customer_id IS NULL) OVER (PARTITION BY email_key) AS guest_id
        FROM {{ woocommerce_orders() }}
    )
),
-- Analytics numbers a customer's orders by date placed, ties by id, and
-- skips the statuses it excludes (is_returning_customer), whether or not
-- the order has its report date yet. Days and months are between the
-- dates placed in the store's time zone, as the numbering goes: days
-- since the customer's previous order, and calendar months since their
-- first, -1 on the first itself, as Shopify's months_since_first_purchase.
headers AS MATERIALIZED (
    SELECT
        *,
        if(excluded, NULL, row_number() OVER w) AS customer_order_number,
        toDate(placed_time, '{{ var("woocommerce_timezone") }}') AS placed_date,
        if(customer_order_number > 1, dateDiff('day', lagInFrame(toNullable(placed_date)) OVER w, placed_date), NULL)
            AS days_since_previous_order,
        if(customer_order_number > 1, dateDiff('month', first_value(placed_date) OVER w, placed_date),
           if(customer_order_number = 1, -1, NULL)) AS months_since_first_order
    FROM identified
    WINDOW w AS (PARTITION BY customer_id, excluded ORDER BY placed_time, id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
{% if is_incremental() %}
-- Orders changed since the last run (woocommerce_keep_changed), and every
-- order of their customers, now and before: a new or cancelled order
-- renumbers the others, and a change of an order's email or account moves
-- other orders between customers. The customer an order had before is the
-- one this table's row of it names; for an order that is gone, the one
-- kept before the pre-hook deleted its row, as an input that collapses old
-- versions may have lost it. An order that moves goes from or to the
-- customer of a changed order; the second round brings in the other
-- customer, whose orders renumber too (a guest joined to an account with
-- a smaller id leaves the one they were joined to).
changed AS MATERIALIZED (SELECT order_id FROM {{ woocommerce_changed_table() }}),
customers AS MATERIALIZED (
    SELECT customer_id FROM headers WHERE id IN changed
    UNION ALL
    SELECT previous_customer_id FROM {{ woocommerce_changed_table() }}
),
moved AS MATERIALIZED (
    SELECT id FROM headers WHERE id IN changed OR customer_id IN customers
    UNION ALL
    SELECT order_id FROM {{ this }} WHERE customer_id IN customers
),
customers_moved AS MATERIALIZED (
    SELECT customer_id FROM headers WHERE id IN moved
    UNION ALL
    SELECT customer_id FROM {{ this }} WHERE order_id IN moved
),
ids AS MATERIALIZED (
    SELECT id FROM headers WHERE id IN changed OR customer_id IN customers_moved
    UNION ALL
    SELECT order_id FROM {{ this }} WHERE customer_id IN customers_moved
),
{% else %}
ids AS MATERIALIZED (
    SELECT id FROM headers
),
{% endif %}
operational AS MATERIALIZED (
    SELECT
        order_id,
        nullIf(ifNull(created_via, ''), '') AS channel,
        ifNull(prices_include_tax, false) AS taxes_included,
        -- Set when the order reaches a paid status of its payment method
        -- (maybe_set_date_paid): processing for a card or bank transfer,
        -- completed for cash on delivery.
        {{ woocommerce_time('date_paid_gmt') }} AS paid_time,
        {{ woocommerce_time('date_completed_gmt') }} AS completed_time,
        ifNull(shipping_total_amount, 0) AS shipping_total_amount,
        ifNull(shipping_tax_amount, 0) AS shipping_tax_amount,
        ifNull(discount_total_amount, 0) AS discount_total_amount
    FROM {{ woocommerce_current('wc_order_operational_data', 'id', 'order_id IN ids') }}
),
shipping_addresses AS MATERIALIZED (
    SELECT
        order_id,
        argMax(nullIf(ifNull(country, ''), ''), id) AS country,
        argMax(nullIf(ifNull(state, ''), ''), id) AS state,
        argMax(nullIf(ifNull(city, ''), ''), id) AS city,
        argMax(nullIf(ifNull(postcode, ''), ''), id) AS postcode
    FROM {{ woocommerce_current('wc_order_addresses', 'id', 'order_id IN ids') }}
    WHERE address_type = 'shipping'
    GROUP BY order_id
),
{% if number_key %}
numbers AS MATERIALIZED (
    SELECT order_id, argMax(ifNull(meta_value, ''), id) AS order_number
    FROM {{ woocommerce_current('wc_orders_meta', 'id', "meta_key = '" ~ number_key ~ "' AND order_id IN ids") }}
    GROUP BY order_id
),
{% endif %}
-- Coupons and fees are items of their own. A fee (positive or negative)
-- is part of the order's total and, as in Analytics' net sales, of its
-- subtotal; coupons are not, their discount is in the lines.
extras_items AS MATERIALIZED (
    SELECT order_item_id, order_id, order_item_type, ifNull(order_item_name, '') AS order_item_name
    FROM {{ woocommerce_current('woocommerce_order_items', 'order_item_id', 'order_id IN ids') }}
    WHERE order_item_type IN ('coupon', 'fee')
),
extras AS MATERIALIZED (
    SELECT
        i.order_id AS order_id,
        arrayMap(c -> c.2, arraySort(groupArrayIf((i.order_item_id, i.order_item_name), i.order_item_type = 'coupon'))) AS discount_codes,
        toDecimal128(sumIf(toDecimal128OrZero(ifNull(m.meta_value, ''), 8), i.order_item_type = 'fee'), 8) AS fee_amount
    FROM extras_items AS i
    LEFT JOIN {{ woocommerce_current('woocommerce_order_itemmeta', 'meta_id',
                                     "meta_key = '_line_total' AND order_item_id IN (SELECT order_item_id FROM extras_items)") }} AS m
        ON m.order_item_id = i.order_item_id
    GROUP BY i.order_id
),
lines AS MATERIALIZED (
    SELECT order_id, count() AS line_item_count, sum(quantity) AS item_quantity
    FROM {{ ref('order_lines') }}
    WHERE order_id IN ids
    GROUP BY order_id
),
refunds AS MATERIALIZED (
    SELECT order_id, sum(refunded_amount) AS refunded_total
    FROM {{ ref('refunds') }}
    WHERE order_id IN ids
    GROUP BY order_id
)
SELECT
    o.id AS order_id,
    {% if number_key %}
    -- The number a sequential order number plugin gave the order, as the
    -- store shows it; the id for an order without one.
    if(n.order_number = '', toString(o.id), n.order_number) AS order_number,
    {% else %}
    toString(o.id) AS order_number,
    {% endif %}
    -- The time the reports date the order by (woocommerce_date_type), and
    -- the time placed while the order has none: a date_paid store dates an
    -- order by payment once it is paid.
    coalesce({{ report_time }}, o.placed_time) AS order_time,
    toDate(order_time, '{{ var("woocommerce_timezone") }}') AS order_date,
    o.placed_time AS placed_time,
    op.paid_time AS paid_time,
    op.completed_time AS completed_time,
    -- Whether the store's reports count the order: its status is not one
    -- they leave out, and it has its report date.
    NOT has({{ excluded }}, o.status) AND {{ report_time }} IS NOT NULL AS in_sales_reports,
    o.status AS status,
    o.customer_id AS customer_id,
    o.customer_email AS customer_email,
    -- Amounts are in the store's currency, converted from the order's
    -- where a multi-currency plugin placed it in another (woocommerce_rates).
    {{ woocommerce_store_currency() }} AS currency,
    o.order_currency AS order_currency,
    {{ woocommerce_total('o.total_amount', 'op.shipping_total_amount', 'op.shipping_tax_amount', 'o.tax_amount') }} AS total,
    -- Shipping after its discounts, without tax (a store enters it so).
    {{ woocommerce_convert('op.shipping_total_amount') }} AS shipping_total,
    -- Tax on goods (tax_amount holds only that) and on shipping.
    {{ woocommerce_convert('o.tax_amount + op.shipping_tax_amount') }} AS tax_total,
    -- Goods after discounts and fees, without tax.
    total - shipping_total - tax_total AS subtotal,
    -- Coupons, without tax.
    {{ woocommerce_convert('op.discount_total_amount') }} AS discount_total,
    {{ woocommerce_convert('e.fee_amount') }} AS fee_total,
    ifNull(rf.refunded_total, toDecimal128(0, 8)) AS refunded_total,
    -- What the order earned after refunds, as the store's reports count
    -- it: the sum of its sales events. A cancelled order the reports leave
    -- out earned nothing (WooCommerce cancels without refunding, even a
    -- paid order); one they count, where the store does not exclude
    -- cancelled orders, is a sale like any other.
    if(is_cancelled AND NOT in_sales_reports, toDecimal128(0, 8), total - refunded_total) AS net_total,
    op.taxes_included AS taxes_included,
    -- Paid only with a payment date: an order in processing or completed
    -- has been paid by card or bank, but cash on delivery is processing
    -- until completed. Failed: no money will come. A full refund sets the
    -- refunded status; a partial one leaves the status. A cancelled
    -- order keeps its payment state. A status neither core nor mapped is
    -- NULL and fails the not_null test.
    multiIf(
        o.core_status NOT IN {{ core_statuses }}, NULL,
        o.core_status = 'failed', 'voided',
        o.core_status = 'refunded', 'refunded',
        refunded_total > 0, 'partially_refunded',
        o.core_status IN ('processing', 'completed', 'cancelled') AND op.paid_time IS NOT NULL, 'paid',
        'unpaid') AS financial_status,
    -- WooCommerce core has no shipments of its own: completed means the
    -- order was shipped or handed over.
    multiIf(
        o.core_status NOT IN {{ core_statuses }}, NULL,
        o.core_status = 'completed', 'fulfilled',
        'unfulfilled') AS fulfillment_status,
    o.core_status = 'cancelled' AS is_cancelled,
    -- checkout, store-api (the block checkout), admin, rest-api, ...
    op.channel AS channel,
    e.discount_codes AS discount_codes,
    length(e.discount_codes) AS discount_code_count,
    a.country AS shipping_country,
    a.state AS shipping_region,
    a.city AS shipping_city,
    a.postcode AS shipping_postcode,
    l.line_item_count AS line_item_count,
    l.item_quantity AS item_quantity,
    o.customer_order_number AS customer_order_number,
    multiIf(customer_order_number = 1, 'new', customer_order_number > 1, 'repeat', NULL) AS new_vs_repeat,
    o.days_since_previous_order AS days_since_previous_order,
    o.months_since_first_order AS months_since_first_order,
    -- When the order's row was synced; the next incremental run starts
    -- from it.
    o.synced_at AS synced_at
FROM headers AS o
LEFT JOIN operational AS op ON op.order_id = o.id
LEFT JOIN shipping_addresses AS a ON a.order_id = o.id
{% if number_key %}
LEFT JOIN numbers AS n ON n.order_id = o.id
{% endif %}
LEFT JOIN extras AS e ON e.order_id = o.id
LEFT JOIN lines AS l ON l.order_id = o.id
LEFT JOIN refunds AS rf ON rf.order_id = o.id
LEFT JOIN {{ woocommerce_rates('ids') }} AS r ON r.order_id = o.id
WHERE o.id IN ids
{{ woocommerce_query_settings() }}
