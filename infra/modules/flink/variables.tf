variable "project" {
  type    = string
  default = "quantlake"
}

variable "flink_role_arn" {
  description = "IAM role Flink assumes at runtime (from iam module)."
  type        = string
}

variable "code_bucket" {
  description = "S3 bucket name where the app zip lives."
  type        = string
}

variable "code_bucket_arn" {
  description = "S3 bucket ARN for the code artifact."
  type        = string
}

variable "flink_apps_src_root" {
  description = "Absolute path to flink-apps/ directory."
  type        = string
}

variable "source_stream_name" {
  description = "Kinesis source stream (news events)."
  type        = string
}

variable "sink_stream_name" {
  description = "Kinesis sink stream (anomalies)."
  type        = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "anomaly_threshold" {
  description = "Minimum event count per 5-min window to emit an anomaly."
  type        = number
  default     = 3
}
