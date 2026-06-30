output "market_events_arn" {
  description = "ARN of the market-events Kinesis stream."
  value       = aws_kinesis_stream.market_events.arn
}

output "market_events_name" {
  description = "Name of the market-events stream (use in CLI/producer config)."
  value       = aws_kinesis_stream.market_events.name
}

output "anomalies_arn" {
  description = "ARN of the anomalies Kinesis stream."
  value       = aws_kinesis_stream.anomalies.arn
}

output "anomalies_name" {
  value = aws_kinesis_stream.anomalies.name
}
