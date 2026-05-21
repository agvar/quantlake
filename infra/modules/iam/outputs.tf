output "glue_job_role_arn"        { value = aws_iam_role.glue_job.arn }
output "lambda_fetcher_role_arn"  { value = aws_iam_role.lambda_fetcher.arn }
output "flink_app_role_arn"       { value = aws_iam_role.flink_app.arn }
output "analyst_readonly_role_arn" { value = aws_iam_role.analyst_readonly.arn }