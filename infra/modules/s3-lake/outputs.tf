output "bucket_names" {
  description = "Map of zone -> bucket name."
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Map of zone -> bucket ARN."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

# Individual handles that later modules (Glue, Athena, Firehose) consume.
output "raw_bucket"            { value = aws_s3_bucket.this["raw"].id }
output "bronze_bucket"         { value = aws_s3_bucket.this["bronze"].id }
output "silver_bucket"         { value = aws_s3_bucket.this["silver"].id }
output "gold_bucket"           { value = aws_s3_bucket.this["gold"].id }
output "athena_results_bucket" { value = aws_s3_bucket.this["athena-results"].id }
