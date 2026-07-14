variable "project" {
  type    = string
  default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "raw_bucket" {
  description = "Raw S3 bucket name (no ARN)."
  type        = string
}

variable "bronze_bucket" {
  description = "Bronze S3 bucket name."
  type        = string
}

variable "glue_role_arn" {
  description = "Pre-existing Glue job execution role ARN (from iam module)."
  type        = string
}

variable "scripts_src_root" {
  description = "Absolute path to the glue-scripts/ directory on disk."
  type        = string
}

variable "tickers" {
  description = "Comma-separated tickers for the raw table's projection enum."
  type        = string
  default     = "AAPL,MSFT,NVDA"
}

variable "job_worker_type" {
  description = "Glue worker size. G.1X = 1 DPU/worker, 16 GB. Smallest general-purpose."
  type        = string
  default     = "G.1X"
}

variable "job_num_workers" {
  description = "Glue worker count. Min 2."
  type        = number
  default     = 2
}
