data "aws_caller_identity" "current" {}

module "iam" {
    source = "../../modules/iam/"
    account_id = data.aws_caller_identity.current.account_id
    region = "us-east-1"
    allowed_admin_ip_cidr = var.allowed_admin_ip_cidr
}

module "kms" {
  source     = "../../modules/kms/"
  project    = "quantlake"
  account_id = data.aws_caller_identity.current.account_id
}

module "s3_lake" {
  source      = "../../modules/s3-lake/"
  project     = "quantlake"
  account_id  = data.aws_caller_identity.current.account_id
  kms_key_arn = module.kms.key_arn
}

output "account_id"                { value = data.aws_caller_identity.current.account_id }
output "glue_job_role_arn"         { value = module.iam.glue_job_role_arn }
output "lambda_fetcher_role_arn"   { value = module.iam.lambda_fetcher_role_arn }
output "flink_app_role_arn"        { value = module.iam.flink_app_role_arn }
output "analyst_readonly_role_arn" { value = module.iam.analyst_readonly_role_arn }

output "kms_key_arn"  { value = module.kms.key_arn }
output "lake_buckets" { value = module.s3_lake.bucket_names }