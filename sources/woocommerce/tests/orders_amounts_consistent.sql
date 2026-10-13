-- An order's amounts add up: nothing negative but fees, no more refunded
-- than paid.
SELECT o.order_id, o.total, o.refunded_total, o.discount_total, o.shipping_total, o.tax_total
FROM {{ ref('orders') }} AS o
WHERE o.total < 0 OR o.refunded_total < 0
   OR o.discount_total < 0 OR o.shipping_total < 0 OR o.tax_total < 0
   OR o.refunded_total > o.total
