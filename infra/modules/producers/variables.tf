variable "project" {
  type    = string
  default = "quantlake"
}

variable "lambda_role_arn" {
  description = "Pre-existing IAM role ARN that Lambdas assume (from iam module)."
  type        = string
}

variable "raw_bucket" {
  description = "Name of the raw S3 bucket where producers land NDJSON."
  type        = string
}

variable "secret_id" {
  description = "Secrets Manager secret name (not ARN) containing API keys."
  type        = string
  default     = "quantlake/api-keys/market-data-providers"
}

variable "tickers" {
  description = "Comma-separated tickers to fetch."
  type        = string
  default     = "AAPL,MSFT,NVDA,AMZN,GOOGL"
}

variable "producers_src_root" {
  description = "Absolute path to producers/ directory holding handler.py files."
  type        = string
}

variable "cmk_arn" {
  description = "Customer-managed KMS key ARN for Lambda env-var encryption at rest."
  type        = string
}
