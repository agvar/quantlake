variable "project" {
  type    = string
  default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for encrypting query results."
  type        = string
}

variable "athena_results_bucket" {
  description = "S3 bucket for Athena query result CSVs / metadata files."
  type        = string
}

variable "bytes_scanned_cutoff_per_query" {
  description = <<EOT
Kill any query that would scan more than this many bytes. 10 GB default =
prevents accidental $50-query mistakes. Adjust up for legitimate large jobs.
EOT
  type        = number
  default     = 10737418240 # 10 GiB
}
