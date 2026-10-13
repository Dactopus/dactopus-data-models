-- An order's amounts add up: nothing negative but fees, no more refunded
-- than paid. An order converted from another currency is rounded part by
-- part, and so is each of its refunds (woocommerce_total): refunds that
-- take it all back may add up to more than its total, by half a cent per
-- rounded part, three parts each for the order and each refund.
SELECT o.order_id, o.total, o.refunded_total, o.discount_total, o.shipping_total, o.tax_total
FROM {{ ref('orders') }} AS o
LEFT JOIN
(
    SELECT order_id, count() AS refunds
    FROM {{ ref('refunds') }}
    GROUP BY order_id
) AS f ON f.order_id = o.order_id
WHERE o.total < 0 OR o.refunded_total < 0
   OR o.discount_total < 0 OR o.shipping_total < 0 OR o.tax_total < 0
   OR o.refunded_total > o.total + if(o.order_currency = o.currency, 0, 0.015 * (ifNull(f.refunds, 0) + 1))
