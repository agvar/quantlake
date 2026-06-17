output "batch_function_name" {
  value = aws_lambda_function.batch.function_name
}

output "news_function_name" {
  value = aws_lambda_function.news.function_name
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}

output "batch_log_group" {
  value = aws_cloudwatch_log_group.batch.name
}

output "news_log_group" {
  value = aws_cloudwatch_log_group.news.name
}
