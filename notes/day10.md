breakup of how PyFlink SQL work- sources/sinks/ transformations are created as TABLE so they can be queried aganist
1. Create a source table - CREATE TABLE source_xyz (...);
2. Create a sink table - CREATE table sink_xyz (...);
3. Insert from source+window function into sink - INSERT into sink_xyz SELECT  ... from TABLE(TUMBLE(...)) group by ..

### Understanding the syntax
table_env.execute_sql(f"""
        INSERT INTO sink_anomalies
        SELECT
            symbol,
            window_start,
            window_end,
            event_count,
            CURRENT_TIMESTAMP AS detected_at
        FROM (
            SELECT
                symbol,
                window_start,
                window_end,
                COUNT(*) AS event_count
            FROM TABLE(
                TUMBLE(
                    TABLE source_market_events,
                    DESCRIPTOR(published_at),
                    INTERVAL '5' MINUTES
                )
            )
            GROUP BY window_start, window_end, symbol
        )
        WHERE event_count >= {threshold}
    """)

    1.  Create the tumble window - format is TUMBLE( TABLE source_xyz, DESCRIPTOR(timestamp field), INTERVAL 'n' MINUTES)
        The tumble function reads the TABLE source_xyz- we need to convert the source_xyz into a TABLE format
        then pass the field that the tumble needs to work on and then define the interval
        The tumble function creates window_start and window_end fields for every row- after slicing the table stream into intervals based on DESCRIPTOR field
        Note the result of the tumble function is only the stamping of the window_start and window_end on every stream row
        The TABLE in the TABLE(TUMBLE...) ensures the tumble function is of the TABLE format so it can be queried, grouped by aganist
        The grouping by the window start, window end and symbol and then calculating the count eventually , calculates the count of events in that tumble window 