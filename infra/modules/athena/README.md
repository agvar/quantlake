# Module: athena

One Athena workgroup with cost guardrails.

## What the workgroup controls

- **Engine version**: AUTO (currently v3 — needed for Iceberg + MERGE INTO)
- **Result location**: `s3://<athena_results_bucket>/queries/`, KMS-encrypted with the lake CMK
- **Query size cap**: 10 GiB per query — anything larger fails immediately (safer than an unbounded surprise)
- **CloudWatch metrics**: enabled, so you can graph query volume + scan bytes per workgroup
- **enforce_workgroup_configuration = true**: clients cannot override any of these settings

## Why a dev-specific workgroup

`primary` (the default workgroup) has no scan cap, no result encryption, and
no enforced settings. Any query anyone runs against `primary` could
accidentally scan a huge table and cost real money. Creating a dedicated
`quantlake-dev` workgroup with guardrails means every accidental
`SELECT * FROM raw_finnhub_news` fails safely at the 10 GiB boundary.

## Cost of the workgroup itself

$0. Workgroups are pure configuration.

## Using it

Athena Console → top bar → Workgroup dropdown → pick `quantlake-dev`.

CLI:

```bash
aws athena start-query-execution \
  --work-group quantlake-dev \
  --query-string "SELECT count(*) FROM quantlake_bronze.finnhub_news" \
  --profile quantlake-admin
```

## What's NOT in this module

- **Silver / gold tables** — those get created via Athena SQL (CTAS / Iceberg
  CREATE TABLE), not Terraform. They're runtime schema, not IaC.
- **Prepared queries / named queries** — could add with `aws_athena_named_query`
  but they're rarely IaC-managed in practice.
- **Data source connectors** (federated queries) — separate topic.
