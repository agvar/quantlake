output "application_name" {
  value = aws_kinesisanalyticsv2_application.anomaly_detector.name
}

output "application_arn" {
  value = aws_kinesisanalyticsv2_application.anomaly_detector.arn
}

output "log_group" {
  value = aws_cloudwatch_log_group.flink_app.name
}

output "code_s3_uri" {
  value = "s3://${var.code_bucket}/${aws_s3_object.app_zip.key}"
}

output "start_command" {
  description = "Run this to start the app after terraform apply."
  value = "aws kinesisanalyticsv2 start-application --application-name ${aws_kinesisanalyticsv2_application.anomaly_detector.name} --run-configuration '{\"FlinkRunConfiguration\":{\"AllowNonRestoredState\":true}}' --profile quantlake-admin"
}

output "stop_command" {
  description = "Run this when done testing -- BEFORE terraform destroy."
  value = "aws kinesisanalyticsv2 stop-application --application-name ${aws_kinesisanalyticsv2_application.anomaly_detector.name} --profile quantlake-admin"
}
