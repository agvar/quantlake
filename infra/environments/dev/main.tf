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
  source                    = "../../modules/producers/"
  project                   = "quantlake"
  lambda_role_arn           = module.iam.lambda_fetcher_role_arn
  raw_bucket                = module.s3_lake.raw_bucket
  cmk_arn                   = module.kms.key_arn
  secret_id                 = "quantlake/api-keys/market-data-providers"
  tickers                   = "AAPL,MSFT,NVDA"
  producers_src_root        = "${path.module}/../../../producers"
  market_events_stream_name = module.kinesis_streams.market_events_name
}

module "kinesis_streams" {
  source               = "../../modules/kinesis-streams/"
  project              = "quantlake"
  kms_key_arn          = module.kms.key_arn
  market_events_shards = 1
  anomalies_shards     = 1
  retention_hours      = 24
}

module "firehose" {
  source            = "../../modules/firehose/"
  project           = "quantlake"
  source_stream_arn = module.kinesis_streams.market_events_arn
  raw_bucket_arn    = "arn:aws:s3:::${module.s3_lake.raw_bucket}"
  kms_key_arn       = module.kms.key_arn
}

module "glue" {
  source           = "../../modules/glue/"
  project          = "quantlake"
  account_id       = data.aws_caller_identity.current.account_id
  raw_bucket       = module.s3_lake.raw_bucket
  bronze_bucket    = module.s3_lake.bronze_bucket
  glue_role_arn    = module.iam.glue_job_role_arn
  scripts_src_root = "${path.module}/../../../glue-scripts"
  tickers          = "AAPL,MSFT,NVDA"
}

module "athena" {
  source                = "../../modules/athena/"
  project               = "quantlake"
  account_id            = data.aws_caller_identity.current.account_id
  kms_key_arn           = module.kms.key_arn
  athena_results_bucket = module.s3_lake.athena_results_bucket
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

output "market_events_stream_arn" { value = module.kinesis_streams.market_events_arn }
output "anomalies_stream_arn"     { value = module.kinesis_streams.anomalies_arn }

output "firehose_delivery_stream_name" { value = module.firehose.delivery_stream_name }
output "firehose_log_group"            { value = module.firehose.log_group_name }

output "glue_raw_database"    { value = module.glue.raw_database }
output "glue_bronze_database" { value = module.glue.bronze_database }
output "glue_bronze_job_name" { value = module.glue.job_name }
output "glue_job_log_groups"  { value = module.glue.job_log_groups }

output "athena_workgroup"       { value = module.athena.workgroup_name }
output "athena_results_prefix"  { value = module.athena.results_prefix }

#output "vpc_id"                  { value = module.networking.vpc_id }
#output "public_subnet_ids"       { value = module.networking.public_subnet_ids }
#output "private_app_subnet_ids"  { value = module.networking.private_app_subnet_ids }
#output "private_data_subnet_ids" { value = module.networking.private_data_subnet_ids }