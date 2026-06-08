# Module: networking

The QuantLake VPC. Three tiers across two AZs, plus VPC endpoints so private
workloads can reach AWS services without a NAT Gateway.

## Layout

```
VPC 10.0.0.0/16  (dns_support + dns_hostnames = ON)
|
+- IGW
|
+- subnet public-a       10.0.0.0/24    AZ a   -> rt-public  -> 0.0.0.0/0 IGW
+- subnet public-b       10.0.1.0/24    AZ b   -> rt-public
+- subnet private-app-a  10.0.10.0/24   AZ a   -> rt-private (NO default route)
+- subnet private-app-b  10.0.11.0/24   AZ b   -> rt-private
+- subnet private-data-a 10.0.20.0/24   AZ a   -> rt-private
+- subnet private-data-b 10.0.21.0/24   AZ b   -> rt-private
|
+- VPC endpoint (Gateway) S3        attached to both route tables
+- VPC endpoint (Gateway) DynamoDB  attached to both route tables
+- VPC endpoint (Interface) each item in var.interface_endpoints  (default empty)
```

## Why three tiers instead of two

The textbook "public + private" split works until you put a database in.
RDS / Redshift / ElastiCache all require a *DB subnet group* spanning >=2 AZs,
and best practice is to keep them in subnets that no compute lives in — that
way an over-permissive SG on the compute tier can't accidentally expose the
database. Separate `private-data-*` subnets give you that isolation today
without re-architecting later.

## Why no NAT Gateway in dev

NAT GW costs ~$32/month per AZ plus $0.045/GB of processed traffic. For dev,
every service we touch (S3, DynamoDB, Glue, Kinesis, Secrets Manager, KMS,
CloudWatch) has a VPC endpoint, so we genuinely never need internet egress.
The first NAT bill people see in production is almost always a Glue or EMR
job reading S3 *without* the Gateway endpoint -- that's the exam-favorite
horror story.

## Gateway vs Interface endpoints (the table)

|                | Gateway                                  | Interface (PrivateLink)           |
|----------------|------------------------------------------|-----------------------------------|
| Services       | **S3 and DynamoDB only**                 | Almost everything else            |
| Cost           | **Free**                                 | ~$7.30/AZ/month + $0.01/GB        |
| Mechanism      | Route table entry, no ENI                | ENI in your subnets, Private DNS  |
| Failure mode   | Wrong route table -> traffic via IGW/NAT | Private DNS off -> traffic leaks  |

We always create the two Gateway endpoints (they're free and prevent the
NAT-cost trap). Interface endpoints are opt-in via `var.interface_endpoints`.

## How to turn on an Interface endpoint later

In `infra/environments/dev/main.tf`, pass the service short names you need:

```hcl
module "networking" {
  source              = "../../modules/networking/"
  interface_endpoints = ["secretsmanager", "kms"]
}
```

Service short names match the suffix after `com.amazonaws.<region>.` --
e.g., `secretsmanager`, `kms`, `glue`, `kinesis-streams`, `monitoring`
(that last one is CloudWatch — the service rename never happened in the
endpoint name).

## Verification commands (after apply)

```bash
# VPC and subnets
aws ec2 describe-vpcs --filters Name=tag:Name,Values=quantlake-vpc --profile quantlake-admin
aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=quantlake-vpc --query 'Vpcs[0].VpcId' --output text --profile quantlake-admin) \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,AZ:AvailabilityZone,CIDR:CidrBlock,Public:MapPublicIpOnLaunch}' \
  --output table --profile quantlake-admin

# Gateway endpoints attached to both route tables
aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-endpoint-type,Values=Gateway \
  --query 'VpcEndpoints[].{Service:ServiceName,RouteTables:RouteTableIds}' \
  --output table --profile quantlake-admin
```

## What we are NOT doing today, and why

- **NAT Gateway** — cost. Add when a workload genuinely needs the public internet.
- **NACLs** — default NACL (allow all) is fine; SGs do the real work. Add NACLs only for compliance / explicit-deny needs.
- **Flow Logs** — extremely useful for debugging endpoint misroutes, but they hit CloudWatch Logs storage costs. We'll add them on Day 25 (observability).
- **Transit Gateway / peering** — single-VPC project, not needed.
