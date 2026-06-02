output "key_arn" {
  description = "ARN of the lakehouse CMK (passed to s3-lake for SSE-KMS)."
  value       = aws_kms_key.lake.arn
}

output "key_id" {
  value = aws_kms_key.lake.key_id
}

output "alias_name" {
  value = aws_kms_alias.lake.name
}
