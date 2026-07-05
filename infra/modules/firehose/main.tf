data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# IAM role for Firehose to read source stream + write destination bucket
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "firehose_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    # Tightening hook: in prod, condition on sts:ExternalId or
    # aws:SourceAccount to defeat cross-account confused-deputy attacks.
  }
}

data "aws_iam_policy_document" "firehose_permissions" {
  # Source stream read
  statement {
    sid = "ReadSourceStream"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
    ]
    resources = [var.source_stream_arn]
  }

  # Destination S3 write
  statement {
    sid = "WriteDestinationBucket"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
    ]
  }

  # KMS via Kinesis (source decrypt)
  statement {
    sid     = "DecryptViaKinesis"
    actions = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # KMS via S3 (destination encrypt + decrypt for backup checks)
  statement {
    sid = "EncryptDecryptViaS3"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # CloudWatch Logs
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${var.project}-*",
    ]
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.project}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_trust.json
  tags               = { Module = "firehose" }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${var.project}-firehose-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_permissions.json
}

# -----------------------------------------------------------------------------
# CloudWatch log group for Firehose error logs.
# Firehose emits delivery events here -- INVALUABLE for debugging silent drops.
#
# We do NOT manage individual log streams as Terraform resources:
# - Firehose auto-creates them on first write (DestinationDelivery, BackupDelivery).
# - Managing them separately just adds import overhead with zero config value;
#   the log_stream_name below is a *label* Firehose writes to, not a
#   dependency on a Terraform-managed resource.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project}-market-events-to-raw"
  retention_in_days = 14
  tags              = { Module = "firehose" }
}

# -----------------------------------------------------------------------------
# The Firehose delivery stream itself
# -----------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "market_events_to_raw" {
  name        = "${var.project}-market-events-to-raw"
  destination = "extended_s3" # always extended_s3 -- "s3" is the legacy type

  kinesis_source_configuration {
    kinesis_stream_arn = var.source_stream_arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    bucket_arn = var.raw_bucket_arn
    role_arn   = aws_iam_role.firehose.arn

    # Where successful records land. Timestamp = approximate Firehose arrival time.
    prefix              = "source=stream-archive/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = var.buffering_size_mb
    buffering_interval = var.buffering_interval_seconds

    compression_format = "GZIP"

    # SSE-KMS at destination -- same CMK as the rest of the lake.
    # Note: Kinesis already encrypted the records in-transit; this re-encrypts
    # them on S3 disk with the destination-side data key.
    kms_key_arn = var.kms_key_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      # Firehose destination-side delivery events. Newer Firehose (2023+) uses
      # "DestinationDelivery"; older docs may show "S3Delivery" -- match reality.
      log_stream_name = "DestinationDelivery"
    }

    # No processing_configuration today; Day 8 adds Glue schema for Parquet conversion.
    # No dynamic_partitioning_configuration today; timestamp-only prefix is enough.
  }

  tags = { Module = "firehose" }

  # Without this depends_on, Terraform might create the Firehose before the
  # role policy is attached, causing a permission-denied at first delivery.
  depends_on = [aws_iam_role_policy.firehose]
}
