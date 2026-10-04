-- Hand-written GA4 export rows for check_numbers.py, loaded into the package
-- input (sources/ga4/input.sql). Each session is a case the package must get
-- right; check_numbers.py derives the expected numbers from these rows.
-- The input database is the query parameter db, as in input.sql.
INSERT INTO {db:Identifier}.events
WITH
    'Array(Tuple(key Nullable(String), value Tuple(string_value Nullable(String), int_value Nullable(Int64), float_value Nullable(Float64), double_value Nullable(Float64))))' AS params_type,
    'Tuple(purchase_revenue Nullable(Float64), purchase_revenue_in_usd Nullable(Float64), tax_value Nullable(Float64), shipping_value Nullable(Float64), transaction_id Nullable(String))' AS ecommerce_type,
    'Tuple(source Nullable(String), medium Nullable(String), campaign_name Nullable(String))' AS campaign_type
SELECT
    r.1 AS event_date,
    toUnixTimestamp64Micro(toDateTime64(r.2, 6, 'UTC')) AS event_timestamp,
    r.3 AS event_name,
    arrayConcat(
        CAST(if(r.5 = 0, [], [('ga_session_id', (NULL, r.5, NULL, NULL))]), params_type),
        CAST(r.6, params_type)) AS event_params,
    r.4 AS user_pseudo_id,
    NULL AS user_id,
    tuple('desktop') AS device,
    tuple('US') AS geo,
    CAST(r.7, ecommerce_type) AS ecommerce,
    tuple(CAST(r.8, campaign_type)) AS session_traffic_source_last_click
FROM (SELECT arrayJoin([
    -- (event_date, time UTC, event_name, user, ga_session_id or 0, params, ecommerce, last-click source)

    -- u1.100: a new export, engaged as the string '1'. The last-click record
    -- (newsletter) wins over the event parameters (google). The thank-you
    -- page is reloaded: purchase T1 is sent twice and counts once.
    ('20250301', '2025-03-01 10:00:00', 'session_start', 'u1', 100, [('session_engaged', ('1', NULL, NULL, NULL)), ('source', ('google', NULL, NULL, NULL)), ('medium', ('organic', NULL, NULL, NULL))], (NULL, NULL, NULL, NULL, NULL), ('newsletter', 'email', 'spring')),
    ('20250301', '2025-03-01 10:00:05', 'page_view',     'u1', 100, [('page_location', ('https://shop.example/', NULL, NULL, NULL))], (NULL, NULL, NULL, NULL, NULL), ('newsletter', 'email', 'spring')),
    ('20250301', '2025-03-01 10:01:00', 'page_view',     'u1', 100, [], (NULL, NULL, NULL, NULL, NULL), ('newsletter', 'email', 'spring')),
    ('20250301', '2025-03-01 10:02:00', 'add_to_cart',   'u1', 100, [], (NULL, NULL, NULL, NULL, NULL), ('newsletter', 'email', 'spring')),
    ('20250301', '2025-03-01 10:05:00', 'purchase',      'u1', 100, [], (100., 110., 10., 5., 'T1'), ('newsletter', 'email', 'spring')),
    ('20250301', '2025-03-01 10:06:00', 'purchase',      'u1', 100, [], (100., 110., 10., 5., 'T1'), ('newsletter', 'email', 'spring')),

    -- u1.200: an old export (no last-click record), engaged as the integer 1,
    -- crosses midnight: one session, dated the day it started.
    ('20250301', '2025-03-01 23:59:00', 'session_start', 'u1', 200, [('session_engaged', (NULL, 1, NULL, NULL)), ('source', ('google', NULL, NULL, NULL)), ('medium', ('organic', NULL, NULL, NULL))], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 00:01:00', 'page_view',     'u1', 200, [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),

    -- u2.300: not engaged; two purchases without a transaction id
    -- ('(not set)' and missing) are two purchases.
    ('20250302', '2025-03-02 09:00:00', 'session_start', 'u2', 300, [('source', ('google', NULL, NULL, NULL)), ('medium', ('cpc', NULL, NULL, NULL)), ('campaign', ('brand', NULL, NULL, NULL))], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 09:00:10', 'page_view',     'u2', 300, [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 09:05:00', 'purchase',      'u2', 300, [], (50., 55., NULL, NULL, '(not set)'), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 09:07:00', 'purchase',      'u2', 300, [], (30., 33., NULL, NULL, NULL), (NULL, NULL, NULL)),

    -- u3.400: no source anywhere; a purchase sent without a value.
    ('20250302', '2025-03-02 12:00:00', 'session_start', 'u3', 400, [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 12:00:10', 'page_view',     'u3', 400, [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 12:03:00', 'purchase',      'u3', 400, [], (NULL, NULL, NULL, NULL, 'T9'), (NULL, NULL, NULL)),

    -- u4: events without a session id, as server-side tracking sends them:
    -- events and a purchase, but no session.
    ('20250302', '2025-03-02 13:00:00', 'page_view',     'u4', 0,   [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL)),
    ('20250302', '2025-03-02 13:10:00', 'purchase',      'u4', 0,   [], (20., 22., NULL, NULL, 'T4'), (NULL, NULL, NULL)),

    -- u5.300: the same ga_session_id as u2's session, another user: another session.
    ('20250302', '2025-03-02 15:00:00', 'session_start', 'u5', 300, [], (NULL, NULL, NULL, NULL, NULL), (NULL, NULL, NULL))
]) AS r)
