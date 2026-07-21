variable "project" {
  type    = string
  default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID (from console-built networking or later import)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs -- task needs egress + auto-assigned public IP because we skipped NAT."
  type        = list(string)
}

variable "kinesis_stream_arn" {
  description = "Stream ARN for the relay to publish to."
  type        = string
}

variable "kinesis_stream_name" {
  description = "Stream name (env var for the container)."
  type        = string
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret containing FINNHUB_KEY."
  type        = string
}

variable "secret_id_string" {
  description = "The secret's name/ID for the SECRET_ID env var."
  type        = string
  default     = "quantlake/api-keys/market-data-providers"
}

variable "kms_key_arn" {
  description = "CMK for decrypting the Secrets Manager secret."
  type        = string
}

variable "tickers" {
  description = "Comma-separated tickers to subscribe."
  type        = string
  default     = "AAPL,MSFT,NVDA"
}

variable "image_tag" {
  description = "ECR image tag to deploy."
  type        = string
  default     = "latest"
}
