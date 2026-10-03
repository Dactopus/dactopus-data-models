{{ config(unique_key='purchase_key', order_by='(purchase_date, purchase_key)') }}
-- One row per purchase. Repeated purchase events with the same transaction id
-- from the same user are one purchase, as the GA4 UI deduplicates them
-- (https://support.google.com/analytics/answer/12313109); a reloaded
-- thank-you page is the usual cause. A purchase without a transaction id is
-- keyed by its event timestamp. Revenue may be NULL: kept, not dropped.
SELECT * FROM (
SELECT
    concat(user_pseudo_id, '.', purchase_id) AS purchase_key,
    user_pseudo_id,
    nullIf(any(tid), '(not set)') AS transaction_id,
    concat(user_pseudo_id, '.', toString(argMin(ga_session_id, event_timestamp))) AS session_key,
    toDate(parseDateTime(argMin(event_date, event_timestamp), '%Y%m%d')) AS purchase_date,
    fromUnixTimestamp64Micro(min(event_timestamp), 'UTC') AS purchase_time,
    argMin(ecommerce.purchase_revenue, event_timestamp) AS revenue,
    argMin(ecommerce.purchase_revenue_in_usd, event_timestamp) AS revenue_usd,
    argMin(ecommerce.tax_value, event_timestamp) AS tax,
    argMin(ecommerce.shipping_value, event_timestamp) AS shipping
FROM
(
    SELECT
        *,
        ecommerce.transaction_id AS tid,
        if(coalesce(tid, '(not set)') = '(not set)', concat('ts:', toString(event_timestamp)), assumeNotNull(tid)) AS purchase_id,
        {{ ga4_param('ga_session_id', 'int') }} AS ga_session_id
    FROM {{ source('ga4_raw', 'events') }}
    WHERE event_name = 'purchase'
    {% if is_incremental() %}
    -- One day earlier than the window, as in sessions.
    AND {{ ga4_raw_window('purchase_date', extra_days=1) }}
    {% endif %}
)
GROUP BY user_pseudo_id, purchase_id
)
{% if is_incremental() %}
WHERE purchase_date >= {{ ga4_window_start('purchase_date') }}
{% endif %}
