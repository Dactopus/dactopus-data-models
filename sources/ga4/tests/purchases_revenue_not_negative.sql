-- Revenue may be missing, never negative: GA4 reports refunds as separate
-- refund events (https://developers.google.com/analytics/devguides/collection/ga4/reference/events#refund).
SELECT purchase_key, revenue, revenue_usd
FROM {{ ref('purchases') }}
WHERE revenue < 0 OR revenue_usd < 0
