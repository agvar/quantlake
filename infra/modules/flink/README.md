# Module: flink

One Amazon Managed Service for Apache Flink (MSF) application, PyFlink runtime,
1 KPU parallelism. Consumes market-events, emits anomalies to the anomalies stream.

## What Terraform creates

- S3 object with the PyFlink zip (`_flink-apps/anomaly_detector.zip` on silver bucket)
- CloudWatch log group + log stream for Flink logs
- `aws_kinesisanalyticsv2_application` in **READY** state (not running)

## Terraform does NOT start the app

Applications must be explicitly started via API/console. This is deliberate:
Terraform managing the RUN state would fight with operator actions (stop for
maintenance, start after deploy, etc.). Start/stop are operational, not IaC.

## Cost while running

- 2 KPUs baseline (1 processing + 1 orchestration) x $0.11/hr = **$0.22/hr**
- Running-application storage: $0.10/GB-month for state snapshots (tiny for us)
- CloudWatch logs storage: negligible at INFO level

At $0.22/hr, 24h/day = ~$160/month. **Do not leave running unattended.**

## The start/test/stop workflow

```bash
APP=quantlake-anomaly-detector

# 1. Start
aws kinesisanalyticsv2 start-application \
  --application-name $APP \
  --run-configuration '{"FlinkRunConfiguration":{"AllowNonRestoredState":true}}' \
  --profile quantlake-admin

# 2. Wait ~2 min for STATUS=RUNNING, then observe
aws kinesisanalyticsv2 describe-application \
  --application-name $APP --profile quantlake-admin \
  --query 'ApplicationDetail.ApplicationStatus'

# 3. Test: invoke news Lambda a few times to push records into market-events
aws lambda invoke --function-name quantlake-news-fetcher \
  --profile quantlake-admin --cli-binary-format raw-in-base64-out \
  --payload '{}' /tmp/test.json

# 4. Read anomalies stream to see output (may take 5+ min due to window close)
SHARD_ITER=$(aws kinesis get-shard-iterator \
  --stream-name quantlake-anomalies \
  --shard-id shardId-000000000000 \
  --shard-iterator-type TRIM_HORIZON \
  --profile quantlake-admin --query ShardIterator --output text)

aws kinesis get-records --shard-iterator $SHARD_ITER \
  --profile quantlake-admin \
  --query 'Records[].Data' --output text | tr '\t' '\n' \
  | while read r; do echo "$r" | base64 --decode; echo; done

# 5. Stop when done
aws kinesisanalyticsv2 stop-application \
  --application-name $APP --profile quantlake-admin

# 6. Verify stopped
aws kinesisanalyticsv2 describe-application \
  --application-name $APP --profile quantlake-admin \
  --query 'ApplicationDetail.ApplicationStatus'
# Expect: STOPPED
```

## Tearing down completely

After stopping:

```bash
cd ~/<repo>/quantlake/infra/environments/dev
terraform destroy -target=module.flink
```

This deletes the Flink app, S3 zip, and log group. Zero further cost.

## Debugging: where the logs live

CloudWatch Logs group: `/aws/kinesis-analytics/quantlake-anomaly-detector`.
Look for `Flink log stream` messages. Common failures:
- `KinesisSourceException: AccessDenied` -- Flink role missing kinesis perms
- `KMSAccessDeniedException` -- missing kms:Decrypt via kinesis (Day 10 inline policy)
- `NullPointerException in TimestampExtractor` -- source record missing `datetime` field
