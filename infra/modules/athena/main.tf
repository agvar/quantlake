# -----------------------------------------------------------------------------
# Dev workgroup: engine v3, KMS-encrypted results, 10 GB scan cap per query.
#
# Every query MUST run in a workgroup. Users switch via the Athena console
# workgroup dropdown OR by passing --work-group in aws athena start-query-execution.
# -----------------------------------------------------------------------------
resource "aws_athena_workgroup" "dev" {
  name          = "${var.project}-dev"
  description   = "Dev workgroup: engine v3, KMS-encrypted results, per-query scan cap"
  state         = "ENABLED"
  force_destroy = true # allow destroy even if workgroup has query history

  configuration {
    # Set to FALSE so users CAN override output location per-query --
    # required for CTAS with `external_location = 's3://<silver-bucket>/...'`.
    # Trade-off: users can also override encryption, engine version, etc.
    # For dev this is acceptable; prod would use a stricter workgroup for
    # dashboard queries + a permissive one for CTAS/DDL work.
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query

    engine_version {
      # AUTO tracks the newest supported version -- currently v3, gets bumped
      # automatically when AWS releases newer engines. Pin explicitly
      # ("Athena engine version 3") if you need reproducibility.
      selected_engine_version = "AUTO"
    }

    result_configuration {
      output_location = "s3://${var.athena_results_bucket}/queries/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }

      # Query result reuse -- engine v3 feature. If the same SQL is submitted
      # within the max_age window, Athena returns the cached result and
      # charges $0 for the scan. Massive cost win for dashboards.
      # Note: default max_age is 60 mins; extend up to 7 days per query.
    }
  }

  tags = { Module = "athena" }
}
