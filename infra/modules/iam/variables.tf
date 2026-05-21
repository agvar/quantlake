variable "project" {
    type = string
    default = "quantlake"
}

variable "account_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_admin_ip_cidr" {
  description = "Your home/office IP in CIDR for the IP-restricted drill"
  type        = string
  default     = "0.0.0.0/0"  # override in dev tfvars
}