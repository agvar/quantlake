variable "project" {
  type    = string
  default = "quantlake"
}

variable "source_stream_arn" {
  description = "ARN of the Kinesis Data Stream that Firehose consumes."
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw S3 bucket that Firehose delivers to."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for source decrypt + destination encrypt."
  type        = string
}

variable "buffering_size_mb" {
  description = "Buffer size in MB before flush. 1-128. Lower = lower latency, higher object count."
  type        = number
  default     = 1
}

variable "buffering_interval_seconds" {
  description = "Time-based buffer in seconds. 60-900. 60 is the floor."
  type        = number
  default     = 60
}
