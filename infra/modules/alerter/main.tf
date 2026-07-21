# =============================================================================
# 1. DynamoDB dedup table
# =============================================================================
resource "aws_dynamodb_table" "dedup" {
  name         = "${var.project}-anomaly-dedup"
  billing_mode = "PAY_PER_REQUEST" # on-demand -- pennies at our volume

  hash_key = "dedup_key"

  attribute {
    name = "dedup_key"
    type = "S"
  }

  # TTL auto-cleans entries after 30 days. Item field: `ttl` (epoch seconds).
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # SSE with customer-managed CMK.
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  # Point-in-time recovery -- backup up to 35 days. Cheap; useful for dev debug.
  point_in_time_recovery {
    enabled = true
  }

  tags = { Module = "alerter" }
}

# =============================================================================
# 2. SNS topic + email subscription
# =============================================================================
resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-anomaly-alerts"
  kms_master_key_id = var.kms_key_arn
  tags              = { Module = "alerter" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # NOTE: after apply, the subscriber must confirm the subscription via
  # the confirmation email from AWS. Unconfirmed subs are inert.
}

# =============================================================================
# 3. Lambda + IAM
# =============================================================================
data "archive_file" "alerter_zip" {
  type        = "zip"
  source_dir  = "${var.consumers_src_root}/anomaly_alerter"
  output_path = "${path.module}/.build/anomaly_alerter.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Read from Kinesis stream (ESM needs these)
  statement {
    sid = "KinesisConsume"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:SubscribeToShard",
    ]
    resources = [var.anomalies_stream_arn]
  }

  # Decrypt CMK-encrypted stream records
  statement {
    sid       = "DecryptViaKinesis"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${var.aws_region}.amazonaws.com"]
    }
  }

  # DynamoDB conditional writes
  statement {
    sid       = "DDBDedupWrite"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.dedup.arn]
  }

  # DynamoDB encryption via CMK
  statement {
    sid       = "DecryptViaDDB"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${var.aws_region}.amazonaws.com"]
    }
  }

  # SNS publish
  statement {
    sid       = "SNSPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  # SNS encryption via CMK
  statement {
    sid       = "EncryptViaSNS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${var.aws_region}.amazonaws.com"]
    }
  }

  # CloudWatch Logs
  statement {
    sid       = "CloudWatchLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${var.account_id}:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-anomaly-alerter-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = { Module = "alerter" }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project}-anomaly-alerter-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project}-anomaly-alerter"
  retention_in_days = 14
  tags              = { Module = "alerter" }
}

resource "aws_lambda_function" "alerter" {
  function_name    = "${var.project}-anomaly-alerter"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  architectures    = ["arm64"]
  filename         = data.archive_file.alerter_zip.output_path
  source_code_hash = data.archive_file.alerter_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      DEDUP_TABLE     = aws_dynamodb_table.dedup.name
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = { Module = "alerter" }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# =============================================================================
# 4. Kinesis Event Source Mapping -- attaches Lambda to the anomalies stream
# =============================================================================
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn                   = var.anomalies_stream_arn
  function_name                      = aws_lambda_function.alerter.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 30

  # Poison-pill isolation: on batch failure, halve the batch to find the bad
  # record instead of retrying the whole batch forever.
  bisect_batch_on_function_error = true

  # Retry cap -- after 5 tries, drop the batch (or send to DLQ if configured).
  maximum_retry_attempts = 5

  # Parallelization factor: 1 = strict per-shard ordering. Higher trades
  # ordering for throughput.
  parallelization_factor = 1
}
