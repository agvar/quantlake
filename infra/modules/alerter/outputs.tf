output "lambda_name"      { value = aws_lambda_function.alerter.function_name }
output "log_group"        { value = aws_cloudwatch_log_group.lambda.name }
output "dedup_table_name" { value = aws_dynamodb_table.dedup.name }
output "sns_topic_arn"    { value = aws_sns_topic.alerts.arn }
