variable "allowed_admin_ip_cidr" {
  description = "Home IP in CIDR notation for the analyst role assumption drill"
  type        = string
}

variable "vpc_id" {
  description = "Console-built VPC ID from Day 4."
  type        = string
}

variable "public_subnet_ids" {
  description = "Console-built public subnet IDs from Day 4."
  type        = list(string)
}

variable "alert_email" {
  description = "Email address for anomaly alerts (SNS)."
  type        = string
}

variable "market_data_secret_arn" {
  description = "Full ARN of the Secrets Manager secret with API keys."
  type        = string
}