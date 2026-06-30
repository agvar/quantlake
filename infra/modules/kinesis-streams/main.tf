# -----------------------------------------------------------------------------
# Stream 1: market-events
#   Producers (Day 7+): news Lambda, ticker Lambda, WebSocket relay (Day 11)
#   Consumers (Day 8+): Flink anomaly detector, Firehose -> S3 bronze
# -----------------------------------------------------------------------------
resource "aws_kinesis_stream" "market_events" {
  name             = "${var.project}-market-events"
  shard_count      = var.market_events_shards
  retention_period = var.retention_hours

  # PROVISIONED -- fixed shards, cheapest at known low throughput.
  # Switch to ON_DEMAND if traffic becomes spiky/unknown.
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  # SSE-KMS with the lake CMK. Encryption at rest is on; the data key is
  # transparently fetched from KMS by Kinesis. Note: switching encryption
  # is online (no replay loss).
  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  # Shard-level metrics in CloudWatch. The two write/read throttle metrics
  # are the single most useful early warning of hot shards.
  shard_level_metrics = var.enable_shard_metrics ? [
    "IncomingBytes",
    "OutgoingBytes",
    "IncomingRecords",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds",
  ] : []

  tags = {
    Module  = "kinesis-streams"
    Purpose = "market-events ingest"
  }
}

# -----------------------------------------------------------------------------
# Stream 2: anomalies
#   Producers: Flink anomaly detector (Day 10)
#   Consumers: Lambda alerting (Day 12), Firehose -> S3 gold (Day 17)
# -----------------------------------------------------------------------------
resource "aws_kinesis_stream" "anomalies" {
  name             = "${var.project}-anomalies"
  shard_count      = var.anomalies_shards
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  shard_level_metrics = var.enable_shard_metrics ? [
    "IncomingBytes",
    "OutgoingBytes",
    "WriteProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds",
  ] : []

  tags = {
    Module  = "kinesis-streams"
    Purpose = "flink anomaly output"
  }
}
