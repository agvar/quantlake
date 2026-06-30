variable "project" {
  type    = string
  default = "quantlake"
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for stream encryption at rest."
  type        = string
}

variable "market_events_shards" {
  description = <<EOT
Shard count for the market-events stream. Each shard: 1 MB/s or 1,000 records/s
ingress, 2 MB/s shared egress. Day 6 dev: 1 shard is overkill but cheapest
($0.015/hour). Reshard when consistent (5-min sustained) usage exceeds 80%.
EOT
  type        = number
  default     = 1
}

variable "anomalies_shards" {
  description = "Shard count for the anomalies stream (Flink output)."
  type        = number
  default     = 1
}

variable "retention_hours" {
  description = "Stream retention. 24 default, max 8760 (365d). Past 7d adds extended-retention cost."
  type        = number
  default     = 24
}

variable "enable_shard_metrics" {
  description = "Emit shard-level CloudWatch metrics. Tiny cost; huge debug value for hot shards."
  type        = bool
  default     = true
}
