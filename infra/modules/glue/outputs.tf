output "raw_database" {
  value = aws_glue_catalog_database.raw.name
}

output "bronze_database" {
  value = aws_glue_catalog_database.bronze.name
}

output "silver_database" {
  value = aws_glue_catalog_database.silver.name
}

output "gold_database" {
  value = aws_glue_catalog_database.gold.name
}

output "raw_finnhub_table" {
  value = aws_glue_catalog_table.raw_finnhub_news.name
}

output "raw_alpha_vantage_table" {
  value = aws_glue_catalog_table.raw_alpha_vantage_bars.name
}

output "raw_stream_archive_table" {
  value = aws_glue_catalog_table.raw_stream_archive.name
}

output "job_name" {
  value = aws_glue_job.raw_to_bronze_finnhub.name
}

output "job_log_groups" {
  description = "Glue writes to shared groups; no per-job group by default."
  value = {
    output = "/aws-glue/jobs/output"
    error  = "/aws-glue/jobs/error"
  }
}
