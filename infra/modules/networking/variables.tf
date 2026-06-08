variable "project" {
  description = "Project tag/name prefix."
  type        = string
  default     = "quantlake"
}

variable "vpc_cidr" {
  description = "VPC CIDR block. /16 is assumed by the subnet math in main.tf."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. 2 AZs recommended for dev; 3 for prod."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "interface_endpoints" {
  description = <<EOT
List of AWS service short names (no "com.amazonaws.<region>." prefix) for which to create
Interface VPC endpoints. EACH endpoint costs ~$7.30/month per AZ + per-GB processing,
so leave this empty until a real in-VPC consumer needs the service.
Examples: ["secretsmanager", "kms", "kinesis-streams", "glue", "monitoring"]
EOT
  type        = list(string)
  default     = []
}
