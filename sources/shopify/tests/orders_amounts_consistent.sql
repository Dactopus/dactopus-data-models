-- An order's amounts add up: nothing negative, no more refunded than paid,
-- and its lines after discounts and without tax make its subtotal (total
-- less shipping and tax). Amounts are in cents, so a cent of difference is
-- allowed for rounding; the development store's orders match exactly.
SELECT o.order_id, o.total, o.refunded_total, o.subtotal, l.line_total
FROM {{ ref('orders') }} AS o
LEFT JOIN (SELECT order_id, sum(line_total) AS line_total FROM {{ ref('order_lines') }} GROUP BY order_id) AS l
    ON l.order_id = o.order_id
WHERE o.discount_total < 0 OR o.shipping_total < 0 OR o.tax_total < 0
   OR o.refunded_total > o.total
   OR abs(o.subtotal - l.line_total) > 0.01
