# Module: kms

A single customer-managed symmetric CMK that encrypts every QuantLake
lakehouse bucket via SSE-KMS.

## Design notes

- **Key rotation** is enabled (`enable_key_rotation = true`). AWS rotates the
  backing key material yearly; the key ID and ARN stay the same, so nothing
  downstream breaks.
- **Key policy = account-root delegation.** The policy only grants the account
  root `kms:*`. That does *not* mean everyone can use the key — it means IAM
  identity-based policies are *permitted to grant* key usage. The actual
  Decrypt / GenerateDataKey grants live in the `iam` module's role policies.
  This is the AWS-recommended pattern (key policy opens the door; IAM decides
  who walks through).
- **Why a CMK instead of SSE-S3?** A CMK gives us a CloudTrail audit trail of
  every encrypt/decrypt, the ability to disable the key to instantly cut off
  access, and per-key access control. The cost (KMS API calls) is neutralised
  by enabling **S3 Bucket Key** on each bucket (see the `s3-lake` module),
  which cuts KMS calls ~99%.
- Deepened on **Day 18**: we tighten the IAM `kms_key_arn` from `key/*` to this
  exact key ARN, and may add grant constraints / `kms:ViaService` conditions.

## Outputs

| Output | Use |
|---|---|
| `key_arn` | Passed to `s3-lake` as `kms_key_arn` for bucket encryption |
| `key_id` | Convenience for CLI / console lookups |
| `alias_name` | `alias/quantlake-lake` — human-friendly handle |
