output "delivery_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.market_events_to_raw.name
}

output "delivery_stream_arn" {
  value = aws_kinesis_firehose_delivery_stream.market_events_to_raw.arn
}

output "firehose_role_arn" {
  value = aws_iam_role.firehose.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.firehose.name
}
