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

variable "anomalies_stream_arn" {
  description = "Kinesis stream Lambda consumes."
  type        = string
}

variable "kms_key_arn" {
  description = "Lake CMK for Kinesis decrypt + SNS + DDB encryption."
  type        = string
}

variable "consumers_src_root" {
  description = "Absolute path to consumers/ directory."
  type        = string
}

variable "alert_email" {
  description = "Where anomaly alerts go. Must be confirmed after creation."
  type        = string
}
