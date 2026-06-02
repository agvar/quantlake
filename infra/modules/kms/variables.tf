variable "project" {
  type    = string
  default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "deletion_window_days" {
  description = "Days before a scheduled key deletion actually happens (7-30)."
  type        = number
  default     = 7
}
