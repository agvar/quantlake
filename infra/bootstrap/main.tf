terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
    region = "us-east-1"
    profile = "quantlake-admin"
    default_tags {
        tags = {
            Project = "quantlake"
            Env     = "shared"
            Owner   = "dragonslayer"
            Module  = "bootstrap"
        }
  }
}

data "aws_caller_identity" "current" {}

locals {
    state_bucket_name = "quantlake-tfstate-${data.aws_caller_identity.current.account_id}"
    lock_table_name = "qauntlake-tfstate-lock"
}

resource "aws_s3_bucket" "tfstate"{
    bucket = local.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate"{
    bucket = aws_s3_bucket.tfstate.id
    versioning_configuration { status =  "Enabled"}
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock"{
    name = local.lock_table_name
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"
    attribute {
        name = "LockID"
        type = "S"
    }
    point_in_time_recovery {enabled= true}
}

output "state_bucket_name" {value = aws_s3_bucket.tfstate.id}
output "lock_table_name" {value = aws_dynamodb_table.tfstate_lock.id}
output "account_id" {value = data.aws_caller_identity.current.account_id}
 