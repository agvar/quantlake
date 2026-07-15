output "workgroup_name" {
  value = aws_athena_workgroup.dev.name
}

output "workgroup_arn" {
  value = aws_athena_workgroup.dev.arn
}

output "results_prefix" {
  description = "S3 URI prefix where query results land."
  value       = "s3://${var.athena_results_bucket}/queries/"
}
