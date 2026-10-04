-- Input of the GA4 package: the GA4 BigQuery export, one row per event.
-- Only the columns the package reads, with types from the official export
-- schema (https://support.google.com/analytics/answer/7029846).
-- Any transport may deliver more columns; it must deliver these.
-- The database is a query parameter, the package's ga4_input_database:
--   clickhouse client --param_db=ga4_raw --multiquery < input.sql
CREATE DATABASE IF NOT EXISTS {db:Identifier};

CREATE TABLE IF NOT EXISTS {db:Identifier}.events
(
    event_date String,                -- YYYYMMDD in the property's time zone
    event_timestamp Int64,            -- microseconds, UTC
    event_name String,
    event_params Array(Tuple(
        key Nullable(String),
        value Tuple(
            string_value Nullable(String),
            int_value Nullable(Int64),
            float_value Nullable(Float64),
            double_value Nullable(Float64)))),
    user_pseudo_id String,
    user_id Nullable(String),
    device Tuple(category Nullable(String)),
    geo Tuple(country Nullable(String)),
    ecommerce Tuple(
        purchase_revenue Nullable(Float64),
        purchase_revenue_in_usd Nullable(Float64),
        tax_value Nullable(Float64),
        shipping_value Nullable(Float64),
        transaction_id Nullable(String)),
    -- The record since July 2024, cross_channel_campaign in it since October
    -- 2024; NULL in older exports.
    session_traffic_source_last_click Tuple(
        cross_channel_campaign Tuple(
            source Nullable(String),
            medium Nullable(String),
            campaign_name Nullable(String)))
)
ENGINE = MergeTree
ORDER BY (event_date, event_name, user_pseudo_id);
