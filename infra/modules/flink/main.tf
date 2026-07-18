# -----------------------------------------------------------------------------
# Package the PyFlink app as a zip. MSF loads it as the app entry point.
# -----------------------------------------------------------------------------
data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = "${var.flink_apps_src_root}/anomaly-detector"
  output_path = "${path.module}/.build/anomaly_detector.zip"
  # Flat zip: main.py + Kinesis connector JAR at zip root.
  # README stays out of the deployment package. Connector JAR must
  # be present locally in flink-apps/anomaly-detector/ before terraform apply.
  excludes    = ["__pycache__", "README.md"]
}

resource "aws_s3_object" "app_zip" {
  bucket = var.code_bucket
  key    = "_flink-apps/anomaly_detector.zip"
  source = data.archive_file.app_zip.output_path
  etag   = data.archive_file.app_zip.output_md5
}

# -----------------------------------------------------------------------------
# CloudWatch log group for the Flink app. MSF writes JobManager +
# TaskManager logs here. Pre-create to control retention (default is
# Never-expire and costs add up quickly).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flink_app" {
  name              = "/aws/kinesis-analytics/${var.project}-anomaly-detector"
  retention_in_days = 14
  tags              = { Module = "flink" }
}

resource "aws_cloudwatch_log_stream" "flink_app" {
  # MSF console default names its log stream "kinesis-analytics-log-stream".
  # Match that so terraform import lines up cleanly.
  name           = "kinesis-analytics-log-stream"
  log_group_name = aws_cloudwatch_log_group.flink_app.name
}

# -----------------------------------------------------------------------------
# The Flink application itself. Created in READY state (not running).
# Start it via: aws kinesisanalyticsv2 start-application ...
# -----------------------------------------------------------------------------
resource "aws_kinesisanalyticsv2_application" "anomaly_detector" {
  name                   = "${var.project}-anomaly-detector"
  runtime_environment    = "FLINK-1_19"
  service_execution_role = var.flink_role_arn

  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = var.code_bucket_arn
          file_key   = aws_s3_object.app_zip.key
        }
      }
      code_content_type = "ZIPFILE"
    }

    # Runtime properties passed to the PyFlink app as PROPERTY_GROUP_* env vars.
    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          # Path is relative to the zip's root. Zip must be flat: main.py
          # and the JAR at the top level.
          python  = "main.py"
          # MSF zip validator requires at least one JAR in the package,
          # even though Flink 1.19 has the Kinesis connector bundled at
          # runtime. This satisfies the validator.
          jarfile = "flink-sql-connector-kinesis-4.3.0-1.19.jar"
        }
      }

      property_group {
        property_group_id = "kinesis.config"
        property_map = {
          "source.stream" = var.source_stream_name
          "sink.stream"   = var.sink_stream_name
          "aws.region"    = var.aws_region
        }
      }

      property_group {
        property_group_id = "anomaly.config"
        property_map = {
          "threshold" = tostring(var.anomaly_threshold)
        }
      }
    }

    flink_application_configuration {
      # Checkpointing: enabled with 60s interval. Exactly-once for source+sink
      # both requires this to be on. Turn off only for at-most-once test runs.
      checkpoint_configuration {
        configuration_type            = "CUSTOM"
        checkpointing_enabled         = true
        checkpoint_interval           = 60000 # 60 sec
        min_pause_between_checkpoints = 5000  # 5 sec
      }

      # Monitoring: application-level metrics + INFO logs.
      # metrics_level: TASK (per-operator, most detailed) is expensive; APPLICATION is enough.
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      # Parallelism: 1 parallel task per KPU. auto_scaling disabled for dev
      # so cost stays predictable.
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = 1
        parallelism_per_kpu  = 1
        auto_scaling_enabled = false
      }
    }

    # No snapshots for dev -- cheaper start, faster tear-down. Prod would enable.
    application_snapshot_configuration {
      snapshots_enabled = false
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_app.arn
  }

  tags = { Module = "flink" }

  depends_on = [
    aws_s3_object.app_zip,
    aws_cloudwatch_log_stream.flink_app,
  ]
}
