# Day 1 — Foundations

## What I did
- Hardened account: MFA on root, IAM Identity Center user dragonslayer-de
- Budget alarm at $25/$50/$75, Cost Anomaly Detection enabled
- AWS CLI configured for SSO (no long-lived access keys)
- quantlake repo initialized with Terraform S3 backend + DynamoDB lock
- usage of Makefile to run startup scripts- creates separate groups within the Makefile 
    - each group can be run using make <groupname>
    - makefile is similar to a batch script that runs the multiple steps in the project
- usage of git tags to track every day progress
- usage of sso login to access AWS resources
    - aws sso login --profile quantlake-admin

## What surprised me
- using s3 as the state file and dynamodb as the lock table

## What I'm still confused about
- how does the dynamodb lock work? does the hash key need to be LockID