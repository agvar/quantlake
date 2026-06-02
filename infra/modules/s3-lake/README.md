# Module: s3-lake

The five buckets that form the QuantLake medallion lakehouse, plus the
Athena query-results bucket.

| Zone | Bucket | Role | Lifecycle |
|---|---|---|---|
| raw | `quantlake-raw-<acct>` | Immutable landing zone, source of truth | → STANDARD_IA @30d → GLACIER_IR @90d; old versions purged @7d |
| bronze | `quantlake-bronze-<acct>` | Cleaned / typed, still source-shaped | Standard; old versions @14d |
| silver | `quantlake-silver-<acct>` | Conformed, joined, deduped | Standard; old versions @14d |
| gold | `quantlake-gold-<acct>` | Business aggregates for BI | Standard; old versions @30d |
| athena-results | `quantlake-athena-results-<acct>` | Query output spill (transient) | Current objects expire @7d |

## Controls on every bucket

- **Versioning** — every overwrite/delete is recoverable.
- **SSE-KMS with the lake CMK** + **`bucket_key_enabled = true`**.
  The S3 Bucket Key caches a bucket-level data key so S3 stops calling KMS on
  every single object operation — **~99% fewer KMS API calls** and the matching
  cost/throttle savings. This is the single most exam-relevant line in the
  module.
- **Block Public Access** — all four switches on. A data lake should never be
  publicly reachable; this makes a public bucket impossible even if someone
  later attaches a bad policy or ACL.
- **`abort_incomplete_multipart_upload`** @7d — silently deletes failed
  multipart uploads that otherwise bill forever (a real, invisible cost leak).

## Why raw transitions but the others don't

`raw` is write-once / read-rarely after ingestion — perfect for cold storage
classes. `bronze`/`silver`/`gold` are queried by Athena/Redshift and must stay
in Standard (ms latency). For all of them we still expire *noncurrent* versions
quickly: old versions are just safety nets, not query targets.

## Why the bucket names embed the account ID

S3 bucket names are **globally unique across all AWS accounts**. Suffixing the
account ID avoids collisions and matches the predicted ARNs already baked into
the `iam` module's role policies.

## Verifying the Bucket Key is on

```bash
aws s3api get-bucket-encryption \
  --bucket quantlake-raw-<acct> --profile quantlake-admin
# expect: "BucketKeyEnabled": true and SSEAlgorithm "aws:kms"
```
