"""
QuantLake anomaly detector -- PyFlink Table API application.

Reads news events from Kinesis (quantlake-market-events), computes a tumbling
5-minute count per symbol, and emits an anomaly record when the count exceeds
3 news items in a window (a signal that something notable happened for that
ticker).

Deployed to Amazon Managed Service for Apache Flink (MSF), runtime Flink 1.19.

Runtime properties (set via MSF's PropertyGroups -> environment_properties in
Terraform):
- kinesis.source.stream   (e.g. quantlake-market-events)
- kinesis.sink.stream     (e.g. quantlake-anomalies)
- aws.region              (e.g. us-east-1)
- anomaly.threshold       (int; default 3)
"""

import json
import os
from pyflink.table import EnvironmentSettings, TableEnvironment


# MSF injects app properties as a JSON file inside the running container.
# This path is fixed by the MSF runtime and documented by AWS.
APPLICATION_PROPERTIES_FILE_PATH = "/etc/flink/application_properties.json"


def get_application_properties():
    """Load the MSF-injected properties file. Returns a list of property-group dicts."""
    if os.path.isfile(APPLICATION_PROPERTIES_FILE_PATH):
        with open(APPLICATION_PROPERTIES_FILE_PATH, "r") as f:
            return json.load(f)
    # Local-dev fallback: file not present, return empty list; caller uses defaults.
    print(f"[warn] Properties file {APPLICATION_PROPERTIES_FILE_PATH} not found; using defaults.")
    return []


def property_map(all_props, property_group_id):
    """Return the PropertyMap dict for a given group ID, or {} if absent."""
    for prop in all_props:
        if prop.get("PropertyGroupId") == property_group_id:
            return prop.get("PropertyMap", {})
    return {}


def main():
    # Streaming mode is what MSF expects for continuous processing.
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = TableEnvironment.create(settings)

    # ---- runtime configuration from MSF property groups ----
    all_props     = get_application_properties()
    kinesis_cfg   = property_map(all_props, "kinesis.config")
    anomaly_cfg   = property_map(all_props, "anomaly.config")

    source_stream = kinesis_cfg.get("source.stream", "quantlake-market-events")
    sink_stream   = kinesis_cfg.get("sink.stream",   "quantlake-anomalies")
    region        = kinesis_cfg.get("aws.region",    "us-east-1")
    threshold     = int(anomaly_cfg.get("threshold", 3))

    # ---- SOURCE TABLE ----
    # `WATERMARK FOR published_at AS published_at - INTERVAL '30' SECOND`
    # tells Flink to expect events up to 30s late. Windows close only after
    # the watermark passes their end -- balances latency vs late-arrival tolerance.
    table_env.execute_sql(f"""
        CREATE TABLE source_market_events (
            symbol         STRING,
            headline       STRING,
            source_val     STRING,
            dedup_key      STRING,
            fetched_at     STRING,
            `datetime`     BIGINT,
            published_at   AS TO_TIMESTAMP_LTZ(`datetime` * 1000, 3),
            WATERMARK FOR published_at AS published_at - INTERVAL '30' SECOND
        ) WITH (
            'connector'            = 'kinesis',
            'stream'               = '{source_stream}',
            'aws.region'           = '{region}',
            'scan.stream.initpos'  = 'LATEST',
            'format'               = 'json',
            'json.ignore-parse-errors' = 'true'
        )
    """)

    # ---- SINK TABLE ----
    # Kinesis sink; partitioned by symbol so same-symbol anomalies land on the
    # same shard downstream (helpful for stateful consumers).
    table_env.execute_sql(f"""
        CREATE TABLE sink_anomalies (
            symbol         STRING,
            window_start   TIMESTAMP(3),
            window_end     TIMESTAMP(3),
            event_count    BIGINT,
            detected_at    TIMESTAMP(3)
        ) WITH (
            'connector'   = 'kinesis',
            'stream'      = '{sink_stream}',
            'aws.region'  = '{region}',
            'format'      = 'json',
            'sink.partitioner-field-delimiter' = '|',
            'sink.producer.record-max-buffered-time' = '100'
        )
    """)

    # ---- ANOMALY DETECTION QUERY ----
    # Tumbling 5-minute window, per symbol; emit record when count >= threshold.
    # TUMBLE table function is the Flink 1.13+ way to declare windows in SQL.
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


if __name__ == "__main__":
    main()
