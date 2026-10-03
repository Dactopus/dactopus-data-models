{{ config(unique_key='event_date', order_by='(event_date, event_name)') }}
SELECT
    if(ga_session_id IS NULL, NULL, concat(user_pseudo_id, '.', toString(ga_session_id))) AS session_key,
    user_pseudo_id,
    ga_session_id,
    toDate(parseDateTime(event_date, '%Y%m%d')) AS event_date,
    fromUnixTimestamp64Micro(event_timestamp, 'UTC') AS event_time,
    event_name,
    {{ ga4_param('page_location', 'string') }} AS page_location,
    {{ ga4_param('page_title', 'string') }} AS page_title,
    device.category AS device_category,
    geo.country AS country
FROM
(
    SELECT *, {{ ga4_param('ga_session_id', 'int') }} AS ga_session_id
    FROM {{ source('ga4_raw', 'events') }}
    -- Filter here: in the outer query the alias event_date (Date) would
    -- shadow the raw column (String).
    {% if is_incremental() %}
    WHERE {{ ga4_raw_window('event_date') }}
    {% endif %}
)
