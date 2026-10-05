{{ config(unique_key='refund_id', order_by='(refund_date, refund_id)') }}
-- One row per refund, its latest version (input.sql). Refunds of test
-- orders are left out. The amount is what was paid back: refunded lines,
-- shipping and adjustments together (totalRefundedSet); it equals the
-- order's totalRefundedSet summed over its refunds (seen on a development
-- store), so orderAdjustments are not needed.
SELECT
    r.id AS refund_id,
    r.order_id AS order_id,
    -- Date of the refund in the shop's time zone.
    toDate(r.created_at, '{{ var("shopify_timezone") }}') AS refund_date,
    r.created_at AS refund_time,
    r.updated_at AS updated_at,
    r.total_refunded AS refunded_amount,
    -- Items refunded; 0 for a refund of shipping or an amount alone.
    rl.quantity AS refunded_quantity
FROM {{ shopify_latest('refunds', 'id') }} AS r
LEFT JOIN
(
    SELECT refund_id, refund_updated_at, sum(quantity) AS quantity
    FROM
    (
        SELECT * FROM {{ source('shopify_raw', 'refund_lines') }}
        ORDER BY loaded_at DESC
        LIMIT 1 BY refund_id, line_item_id, refund_updated_at
    )
    GROUP BY refund_id, refund_updated_at
) AS rl ON rl.refund_id = r.id AND rl.refund_updated_at = r.updated_at
WHERE r.order_id IN (SELECT order_id FROM {{ ref('orders') }})
{% if is_incremental() %}
AND r.id IN (SELECT id FROM {{ source('shopify_raw', 'refunds') }} WHERE updated_at >= {{ shopify_window_start('updated_at') }})
{% endif %}
