-- An order's amounts add up: nothing negative, no more refunded than paid
-- (tips included; gift cards apart) nor more gift cards refunded than sold,
-- and its lines after discounts and without tax make its subtotal (total
-- less shipping and tax). Amounts are in cents, so a cent of difference
-- is allowed for rounding; the development store's orders match exactly.
-- Lines are compared only when those of the order's latest version are
-- in: a run can land between the insert of a version and of its lines,
-- and the next run completes the order.
SELECT o.order_id, o.total, o.refunded_total, o.subtotal, l.line_total
FROM {{ ref('orders') }} AS o
LEFT JOIN
(
    SELECT order_id, order_updated_at, sum(line_total) AS line_total
    FROM {{ ref('order_lines') }}
    GROUP BY order_id, order_updated_at
) AS l ON l.order_id = o.order_id AND l.order_updated_at = o.updated_at
WHERE o.total < 0 OR o.refunded_total < 0
   OR o.discount_total < 0 OR o.shipping_total < 0 OR o.tax_total < 0
   OR o.refunded_total > o.total + o.tip_total
   OR o.gift_card_refunded_total > o.gift_card_total
   OR (o.order_id, o.updated_at) IN (SELECT order_id, order_updated_at FROM {{ ref('order_lines') }})
      AND abs(o.subtotal - l.line_total) > 0.01
