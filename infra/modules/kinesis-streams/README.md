# Module: kinesis-streams

Two provisioned Kinesis Data Streams, both SSE-KMS encrypted with the lake CMK.

| Stream | Producers (planned) | Consumers (planned) |
|---|---|---|
| `quantlake-market-events` | news Lambda (Day 7), ticker Lambda, WebSocket Fargate (Day 11) | Flink anomaly detector (Day 10), Firehose -> S3 (Day 7) |
| `quantlake-anomalies` | Flink anomaly detector (Day 10) | Lambda alerting (Day 12) |

## Sizing today

1 shard each. That gives:
- 1 MB/s OR 1,000 records/s ingress
- 2 MB/s shared egress

Day 6 actual traffic is < 1 KB/s -- we're nowhere near the limit. The reason to
provision instead of using ON_DEMAND is cost: 1 shard ~ $11/month vs. ON_DEMAND
flat ~ $30/month per stream. Switch to ON_DEMAND if traffic becomes spiky enough
that shard-resizing becomes operational toil.

## Why CMK encryption matters

Kinesis transparently fetches a data key from KMS for every shard's data. With
our lake CMK + the IAM role policies from Day 2, only principals authorized
on the CMK can consume the stream -- a second layer behind the IAM grant.

There is NO equivalent of S3's Bucket Key for Kinesis -- every read/write
fetches a fresh data key. At higher throughputs you'll see KMS API calls
scale linearly with record volume. Monitor `kms.Throttles`.

## Shard-level metrics

We enable the throttle metrics because **the only way to detect a hot shard
proactively** is via `WriteProvisionedThroughputExceeded` (producer side) and
`ReadProvisionedThroughputExceeded` (consumer side). Both fire when individual
shards saturate even if the stream average is fine.

`IteratorAgeMilliseconds` is the most useful consumer-lag metric in AWS:
it's how far behind the youngest unread record your consumer is. If it
grows monotonically, your consumer can't keep up.

## When to reshard

Reshard when sustained shard utilization exceeds 80% over 5 minutes. Two ops:
- **Split**: divide one shard's hash range across two new shards (increases throughput).
- **Merge**: combine two adjacent shards into one (saves cost when load drops).

Each reshard is an online operation: old shards keep serving in-flight reads
until their data ages out (24h+); new shards take all new writes. Producer
partition-key hashing handles the routing transparently.

## Verification commands

```bash
aws kinesis describe-stream-summary \
  --stream-name quantlake-market-events --profile quantlake-admin

aws kinesis list-shards \
  --stream-name quantlake-market-events --profile quantlake-admin
```
