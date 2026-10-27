{# The latest version of each row of an input table (input.sql): the
   greatest version time, and of two loads of the same version the later.
   Sorted by the key first: the key is the table's sorting key (input.sql),
   so ClickHouse reads the parts in that order, merges them as a stream and
   picks each key's first row as it goes, so this pass's memory does not
   grow with the table. Sorted by version first, the whole table with all
   its columns is sorted in memory: 2.4 GB for the lines of 2 million orders
   (#8). The key therefore names the sorting key's columns even where fewer
   identify a row: `order_id, id` for refunds. A table with another sorting
   key gives the same rows, sorted in memory. `where` filters whole keys
   before the sort, so a run sorts only them; `select` names the columns to
   read, for a pass that needs a few of them. #}
{% macro shopify_latest(table, key, version='updated_at', where='true', select='*') -%}
(SELECT {{ select }} FROM {{ source('shopify_raw', table) }} WHERE {{ where }}
 ORDER BY {{ key }}{% if version not in key.replace(' ', '').split(',') %}, {{ version }} DESC{% endif %}, loaded_at DESC LIMIT 1 BY {{ key }})
{%- endmacro %}

{# Settings every model's query ends with. An INSERT ... SELECT buffers the
   rows to insert per insert thread, up to min_insert_block_size_bytes
   each, before it sorts and writes them as a part: with the defaults, 256
   MB times the server's cores (max_insert_threads), 2 GB on 8 cores, while
   the output of a full build is smaller than that, it is all held in
   memory, and the models' own work comes on top (#8: the full build of
   orders for 4 million orders peaked at 2.9 GB, 1.5 GB with these settings;
   with one insert thread the build is about twice as slow). An incremental
   run inserts few rows and is not affected.
   join_use_nulls = 0: a LEFT JOIN without a match fills the joined
   columns with their type's default, 0 for an amount, which the models
   count on (an order without gift cards, a refund without lines); a
   server or profile that sets 1 would make them NULL. #}
{% macro shopify_query_settings() -%}
SETTINGS max_insert_threads = 1, min_insert_block_size_rows = 262144, min_insert_block_size_bytes = 67108864, join_use_nulls = 0
{%- endmacro %}

{# A refund line refunds a gift card sold: its line item is a gift card in
   order_lines. Any version will do, as a line item keeps the flag in all
   of them. orders and refunds both set gift cards apart with this test,
   so their gift card amounts agree. #}
{% macro shopify_refunds_gift_card() -%}
line_item_id IN (SELECT id FROM {{ source('shopify_raw', 'order_lines') }} WHERE is_gift_card)
{%- endmacro %}

{# Keys of an input table loaded since an incremental run's window start:
   the latest load this model has seen minus the lookback. Load time, not
   version time: a row delivered late, by a loader catching up or a
   backfill, carries an old updated_at but a new loaded_at. An empty model
   rereads everything: its max() is 1970-01-01, and DateTime64 goes below
   it without wrapping. #}
{% macro shopify_loaded_since(table, key='id') -%}
(SELECT {{ key }} FROM {{ source('shopify_raw', table) }}
 WHERE loaded_at >= (SELECT max(loaded_at) - INTERVAL {{ var('shopify_lookback_days') }} DAY FROM {{ this }}))
{%- endmacro %}
