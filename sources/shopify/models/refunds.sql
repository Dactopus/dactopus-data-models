{{ config(unique_key='refund_id', order_by='(refund_date, refund_id)') }}
-- One row per refund, its latest version (input.sql). Refunds of test
-- orders are left out. The amount is what was paid back: refunded lines,
-- shipping and adjustments together (totalRefundedSet), less gift cards
-- sold and refunded, as Shopify's sales reports count returns (see
-- orders.sql); it equals the order's refunded_total summed over its
-- refunds (seen on a development store), so orderAdjustments are not
-- needed. A refund of gift cards alone stays, with an amount of 0: a
-- refund's lines may be loaded after it, and an incremental run replaces
-- rows, it does not remove them.
SELECT
    r.id AS refund_id,
    r.order_id AS order_id,
    -- Date of the refund in the shop's time zone.
    toDate(r.created_at, '{{ var("shopify_timezone") }}') AS refund_date,
    r.created_at AS refund_time,
    r.updated_at AS updated_at,
    r.total_refunded - rl.gift_card_amount AS refunded_amount,
    rl.gift_card_amount AS gift_card_amount,
    -- Items refunded, gift cards apart; 0 for a refund of shipping or an
    -- amount alone.
    rl.quantity AS refunded_quantity,
    -- When the version was loaded; the next incremental run starts from it.
    r.loaded_at AS loaded_at
{% if is_incremental() %}
{# Refunds loaded since the last run, refunds whose lines were, and
   refunds of orders whose lines were: a gift card line may be loaded
   after the refund line that pays it back. #}
{% set refunds_changed = "(SELECT id FROM " ~ source('shopify_raw', 'refunds')
    ~ " WHERE id IN " ~ shopify_loaded_since('refunds')
    ~ " OR id IN " ~ shopify_loaded_since('refund_lines', 'refund_id')
    ~ " OR order_id IN " ~ shopify_loaded_since('order_lines', 'order_id') ~ ")" %}
FROM {{ shopify_latest('refunds', 'id', where="id IN " ~ refunds_changed) }} AS r
{% else %}
FROM {{ shopify_latest('refunds', 'id') }} AS r
{% endif %}
LEFT JOIN
(
    SELECT refund_id, refund_updated_at, sumIf(quantity, NOT is_gift_card) AS quantity,
           toDecimal64(sumIf(subtotal + total_tax, is_gift_card), 4) AS gift_card_amount
    FROM (
        SELECT *, line_item_id IN (SELECT id FROM {{ source('shopify_raw', 'order_lines') }} WHERE is_gift_card) AS is_gift_card
        {% if is_incremental() %}
        FROM {{ shopify_latest('refund_lines', 'refund_id, id, refund_updated_at', version='refund_updated_at',
                               where="refund_id IN " ~ refunds_changed) }}
        {% else %}
        FROM {{ shopify_latest('refund_lines', 'refund_id, id, refund_updated_at', version='refund_updated_at') }}
        {% endif %}
    )
    GROUP BY refund_id, refund_updated_at
) AS rl ON rl.refund_id = r.id AND rl.refund_updated_at = r.updated_at
WHERE r.order_id IN (SELECT order_id FROM {{ ref('orders') }})
