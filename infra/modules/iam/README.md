# IAM Module — QuantLake

Creates four IAM roles, each with a trust policy (who can assume) and
inline permission policy (what they can do).

| Role | Trusted principal | Why this role exists |
|---|---|---|
| `quantlake-glue-job-role` | `glue.amazonaws.com` | Runs PySpark Glue ETL jobs that move data raw → bronze → silver → gold |
| `quantlake-lambda-fetcher-role` | `lambda.amazonaws.com` | Producer Lambdas that pull market data from Alpha Vantage/Finnhub and publish to Kinesis |
| `quantlake-flink-app-role` | `kinesisanalytics.amazonaws.com` | Managed Flink: OHLC windows + anomaly detection |
| `quantlake-analyst-readonly-role` | account root (with IP restriction) | Identity Center analysts use this for Athena queries; Lake Formation refines further on Day 19 |

## Design notes

- All policies reference predicted ARNs of resources that don't exist yet
  (S3 buckets in Day 3, Kinesis stream in Day 6, etc.). IAM accepts this
  — policies are not validated against existing resources at creation time.
- KMS permissions are intentionally broad (`kms:key/*`) for Day 2.
  Tightened to a specific CMK on Day 18.
- The analyst role's trust policy includes a `SourceIp` condition — see
  the common-trap drill in the Day 2 notes.