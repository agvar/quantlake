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

#module "networking" {
#  source  = "../../modules/networking/"
#  project = "quantlake"
  # interface_endpoints stays empty for dev to keep cost at $0.
  # Add services as you build the consumers that need them, e.g.:
  # interface_endpoints = ["secretsmanager", "kms"]
#}

module "producers" {
  source             = "../../modules/producers/"
  project            = "quantlake"
  lambda_role_arn    = module.iam.lambda_fetcher_role_arn
  raw_bucket         = module.s3_lake.raw_bucket
  cmk_arn            = module.kms.key_arn
  secret_id          = "quantlake/api-keys/market-data-providers"
  tickers            = "AAPL,MSFT,NVDA"
  producers_src_root = "${path.module}/../../../producers"
}

output "account_id"                { value = data.aws_caller_identity.current.account_id }
output "glue_job_role_arn"         { value = module.iam.glue_job_role_arn }
output "lambda_fetcher_role_arn"   { value = module.iam.lambda_fetcher_role_arn }
output "flink_app_role_arn"        { value = module.iam.flink_app_role_arn }
output "analyst_readonly_role_arn" { value = module.iam.analyst_readonly_role_arn }

output "kms_key_arn"  { value = module.kms.key_arn }
output "lake_buckets" { value = module.s3_lake.bucket_names }

output "batch_fetcher_function_name" { value = module.producers.batch_function_name }
output "news_fetcher_function_name"  { value = module.producers.news_function_name }

#output "vpc_id"                  { value = module.networking.vpc_id }
#output "public_subnet_ids"       { value = module.networking.public_subnet_ids }
#output "private_app_subnet_ids"  { value = module.networking.private_app_subnet_ids }
#output "private_data_subnet_ids" { value = module.networking.private_data_subnet_ids }