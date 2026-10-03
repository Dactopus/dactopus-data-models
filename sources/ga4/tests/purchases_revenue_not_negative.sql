-- Revenue may be missing, never negative: GA4 reports refunds as separate events.
SELECT purchase_key, revenue, revenue_usd
FROM {{ ref('purchases') }}
WHERE revenue < 0 OR revenue_usd < 0
