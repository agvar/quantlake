# Anomaly detector (PyFlink)

## Required companion JAR (not committed to git)

MSF's zip validator requires at least one JAR in the deployment package,
even for PyFlink apps. Download the Flink Kinesis SQL connector once:

```bash
cd flink-apps/anomaly-detector
curl -O https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kinesis/4.3.0-1.19/flink-sql-connector-kinesis-4.3.0-1.19.jar
```

The JAR (~20MB) is in `.gitignore`. Terraform's `archive_file` includes it
in the zip automatically when present.



A single-file PyFlink Table API job that runs on Amazon Managed Service for
Apache Flink. Reads market-events from Kinesis, does a tumbling 5-minute
count per symbol, emits an anomaly record when the count crosses a threshold.

## The pipeline

```
quantlake-market-events (Kinesis, JSON news records)
    -> Flink source table (with event-time + watermark)
    -> tumbling 5-min window, GROUP BY symbol
    -> WHERE event_count >= threshold
    -> Flink sink table
    -> quantlake-anomalies (Kinesis, JSON anomaly records)
```

## Why event-time not processing-time

Market events can arrive out of order (network jitter, retries). Processing-time
windows would misbucket a late AAPL event; event-time windows preserve
temporal accuracy at the cost of some watermark latency (30 sec here).

## Why 30-second watermark

The trade-off:
- Too tight (5s) -> late-arriving events dropped, undercounts anomalies.
- Too loose (5min) -> each window's result waits 5min after its end for
  the watermark; downstream latency ~10min instead of 5.

30s balances the two; production would tune by looking at actual arrival lag.

## Runtime properties

Set via MSF's PropertyGroups (mapped in Terraform):

| Group | Key | Default |
|---|---|---|
| kinesis.config | source.stream | quantlake-market-events |
| kinesis.config | sink.stream | quantlake-anomalies |
| kinesis.config | aws.region | us-east-1 |
| anomaly.config | threshold | 3 |

## Local test (optional)

PyFlink can run locally with `pyflink` package installed, but the Kinesis
connector needs the JAR available. Simpler to iterate on MSF Studio for
Flink SQL changes, then port to this script.

## Deploy

Terraform packages `main.py` into a zip and uploads to S3; MSF references
that zip. Application is created STOPPED; start it via console or
`aws kinesisanalyticsv2 start-application`.

## Tear down (do this!)

MSF costs ~$0.22/hour running. Always stop and destroy after testing:

```bash
aws kinesisanalyticsv2 stop-application \
  --application-name quantlake-anomaly-detector \
  --profile quantlake-admin
# Wait ~30 sec for state STOPPED, then:
cd ~/<repo>/quantlake/infra/environments/dev
terraform destroy -target=module.flink
```
