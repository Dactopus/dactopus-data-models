{{ config(unique_key='session_key', order_by='(session_date, session_key)') }}
-- One row per session. A session is (user_pseudo_id, ga_session_id):
-- ga_session_id is the session start in seconds and repeats across users
-- (https://support.google.com/analytics/answer/9191807). The GA4 UI estimates
-- session counts (HyperLogLog++); counts here are exact and differ slightly.
SELECT * FROM (
SELECT
    concat(user_pseudo_id, '.', toString(assumeNotNull(ga_session_id))) AS session_key,
    user_pseudo_id,
    assumeNotNull(ga_session_id) AS ga_session_id,
    -- Date of the session's first event, in the property's time zone.
    toDate(parseDateTime(argMin(event_date, event_timestamp), '%Y%m%d')) AS session_date,
    fromUnixTimestamp64Micro(min(event_timestamp), 'UTC') AS session_start_time,
    max(engaged_flag) AS is_engaged,
    max(event_name = 'purchase') AS has_purchase,
    countIf(event_name = 'page_view') AS page_views,
    -- Session source as in the GA4 UI (last non-direct click), exported since
    -- October 2024. Older exports: the first source seen in the session's
    -- event parameters; GA4 would credit an earlier non-direct source instead.
    coalesce(any(stslc_source), argMinIf(param_source, event_timestamp, param_source IS NOT NULL), '(not set)') AS source,
    coalesce(any(stslc_medium), argMinIf(param_medium, event_timestamp, param_medium IS NOT NULL), '(not set)') AS medium,
    coalesce(any(stslc_campaign), argMinIf(param_campaign, event_timestamp, param_campaign IS NOT NULL), '(not set)') AS campaign,
    argMinIf(page_location, event_timestamp, page_location IS NOT NULL) AS landing_page,
    argMin(device.category, event_timestamp) AS device_category,
    argMin(geo.country, event_timestamp) AS country
FROM
(
    SELECT
        *,
        {{ ga4_param('ga_session_id', 'int') }} AS ga_session_id,
        -- session_engaged arrives either as the string '1' or as the integer 1.
        {{ ga4_param('session_engaged', 'string') }} = '1' OR {{ ga4_param('session_engaged', 'int') }} = 1 AS engaged_flag,
        {{ ga4_param('source', 'string') }} AS param_source,
        {{ ga4_param('medium', 'string') }} AS param_medium,
        {{ ga4_param('campaign', 'string') }} AS param_campaign,
        {{ ga4_param('page_location', 'string') }} AS page_location,
        session_traffic_source_last_click.cross_channel_campaign.source AS stslc_source,
        session_traffic_source_last_click.cross_channel_campaign.medium AS stslc_medium,
        session_traffic_source_last_click.cross_channel_campaign.campaign_name AS stslc_campaign
    FROM {{ source('ga4_raw', 'events') }}
    -- Events without a session id form no session. Filter here: in the outer
    -- query the alias assumeNotNull(ga_session_id) would shadow this column.
    WHERE ga_session_id IS NOT NULL
    {% if is_incremental() %}
    -- One day earlier than the window: a session that crosses midnight into
    -- the window must be rebuilt whole or not at all.
    AND {{ ga4_raw_window('session_date', extra_days=1) }}
    {% endif %}
)
GROUP BY user_pseudo_id, ga_session_id
)
{% if is_incremental() %}
WHERE session_date >= {{ ga4_window_start('session_date') }}
{% endif %}
