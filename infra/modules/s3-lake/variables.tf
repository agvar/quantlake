variable "project" {
  type    = string
  default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "kms_key_arn" {
  description = "ARN of the lake CMK used for SSE-KMS on every bucket."
  type        = string
}
