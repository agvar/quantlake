# Module: firehose

One Firehose delivery stream that consumes from `quantlake-market-events`
(Kinesis Data Stream) and lands GZIP-compressed JSON in the raw S3 bucket
under `source=stream-archive/year=YYYY/month=MM/day=DD/hour=HH/`.

```
news Lambda ----(PutRecords)----> quantlake-market-events
                                    (Kinesis Data Stream, 1 shard, 24h retention)
                                          |
                                          | (Firehose subscribes as consumer)
                                          v
                          quantlake-market-events-to-raw
                                 (Firehose, buffer 1MB/60s)
                                          |
                                          | (GZIP compress, KMS encrypt)
                                          v
                  s3://quantlake-raw-<acct>/source=stream-archive/
                              year=2026/month=06/day=17/hour=14/...
```

## Why dual-write the news Lambda

The news Lambda still writes directly to S3 (Day 5 path under
`source=finnhub/...`) AND publishes to Kinesis (Day 7 path, lands under
`source=stream-archive/...` via this Firehose). Reasons:

- **Comparison material**: side by side in raw, we can compare object size,
  partition layout, and delivery latency between direct vs streamed.
- **Downstream consumers**: Day 10's Flink job needs the stream too. Without
  the dual-write, we'd lose the S3-direct fast path during the Day 10 work.
- **Failure isolation**: if Kinesis is unavailable, S3 direct still works.
  If S3 direct fails, Kinesis still buffers. Two sinks = independent failure
  modes for an immutable raw zone.

## Buffer hint trade-off

We set 1 MB / 60 seconds. Implications:
- **Object count**: at trickle volume, we get one S3 object per minute per
  active prefix (so per hour per source). That's 24 objects/day for a single
  source -- manageable for Athena.
- **Latency**: first record in a batch waits up to 60 seconds to arrive in S3.
- **Cost**: more, smaller objects = more S3 PUT calls + slightly more Glue
  catalog overhead later. For dev this is fine.

In prod with 100 GB/day, you'd dial up to 128 MB / 60s to get fewer, larger
objects (Parquet+Athena loves big objects).

## Why the IAM role has TWO KMS statements

Firehose reads from a CMK-encrypted Kinesis stream (needs `kms:Decrypt` via
the kinesis service) AND writes to a CMK-encrypted S3 bucket (needs
`kms:GenerateDataKey` via the s3 service). Two services, two `ViaService`
conditions, two statements. Same defense-in-depth pattern as our Lambda role.

## When Firehose silently drops records

The single most-asked exam scenario:

| Symptom | Likely cause | Fix |
|---|---|---|
| Records in stream, none in S3 | Firehose role missing s3:PutObject | Add the grant |
| Records in stream, KMS errors in Firehose logs | Missing kms:Decrypt via kinesis or kms:GenerateDataKey via s3 | Add the matching statement |
| Records land in `errors/processing-failed/` | Lambda transform threw OR record exceeded 1 MB | Inspect the error payload, fix processor or split records |
| Long IteratorAgeMilliseconds, slow S3 delivery | Buffer hints too lazy (size + interval both high) | Lower one |

Always check the CloudWatch log group first --
`/aws/kinesisfirehose/quantlake-market-events-to-raw` / log stream `S3Delivery`.
