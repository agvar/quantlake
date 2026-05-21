locals {
  # Predicted resource ARN patterns — we'll create these in later modules.
  # IAM doesn't validate that resources exist at policy-creation time.
  s3_raw_arn      = "arn:aws:s3:::${var.project}-raw-${var.account_id}"
  s3_bronze_arn   = "arn:aws:s3:::${var.project}-bronze-${var.account_id}"
  s3_silver_arn   = "arn:aws:s3:::${var.project}-silver-${var.account_id}"
  s3_gold_arn     = "arn:aws:s3:::${var.project}-gold-${var.account_id}"
  s3_athena_arn   = "arn:aws:s3:::${var.project}-athena-results-${var.account_id}"

  kinesis_stream_arn = "arn:aws:kinesis:${var.region}:${var.account_id}:stream/${var.project}-market-events"
  kinesis_anomalies_arn = "arn:aws:kinesis:${var.region}:${var.account_id}:stream/${var.project}-anomalies"

  secrets_prefix = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project}/api-keys/*"
  kms_key_arn    = "arn:aws:kms:${var.region}:${var.account_id}:key/*" # tighten in Day 18
}

# =========================================================
# 1. Glue Job Role
# =========================================================
data "aws_iam_policy_document" "glue_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_permissions" {
  # Read raw, write bronze/silver/gold
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.s3_raw_arn, "${local.s3_raw_arn}/*"]
  }
  statement {
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
      "s3:AbortMultipartUpload", "s3:ListBucketMultipartUploads"
    ]
    resources = [
      local.s3_bronze_arn, "${local.s3_bronze_arn}/*",
      local.s3_silver_arn, "${local.s3_silver_arn}/*",
      local.s3_gold_arn,   "${local.s3_gold_arn}/*"
    ]
  }

  # KMS for encrypted reads/writes
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.kms_key_arn]
  }

  # Glue Catalog operations
  statement {
    actions = [
      "glue:GetDatabase", "glue:GetTable", "glue:GetPartitions",
      "glue:CreateTable", "glue:UpdateTable", "glue:BatchCreatePartition",
      "glue:BatchUpdatePartition", "glue:BatchGetPartition"
    ]
    resources = ["*"]  # Glue catalog ARNs are awkward; tighten in production
  }

  # CloudWatch Logs (every role needs this)
  statement {
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream",
      "logs:PutLogEvents", "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:*"]
  }
}

resource "aws_iam_role" "glue_job" {
  name               = "${var.project}-glue-job-role"
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json

  tags = { Purpose = "Glue ETL jobs for bronze_to_silver and silver_to_gold" }
}

resource "aws_iam_role_policy" "glue_job" {
  name   = "${var.project}-glue-job-policy"
  role   = aws_iam_role.glue_job.id
  policy = data.aws_iam_policy_document.glue_permissions.json
}

# =========================================================
# 2. Lambda Fetcher Role (market data producers + enrichment)
# =========================================================
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
  # Read API keys from Secrets Manager
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.secrets_prefix]
  }

  # Decrypt secrets
  statement {
    actions = ["kms:Decrypt"]
    resources = [local.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }

  # Publish to Kinesis stream
  statement {
    actions = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStream"]
    resources = [local.kinesis_stream_arn]
  }

  # CloudWatch Logs
  statement {
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:*"]
  }
}

resource "aws_iam_role" "lambda_fetcher" {
  name               = "${var.project}-lambda-fetcher-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = { Purpose = "Lambda batch fetchers + tick enrichment" }
}

resource "aws_iam_role_policy" "lambda_fetcher" {
  name   = "${var.project}-lambda-fetcher-policy"
  role   = aws_iam_role.lambda_fetcher.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# =========================================================
# 3. Managed Flink Application Role
# =========================================================
data "aws_iam_policy_document" "flink_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flink_permissions" {
  statement {
    actions = [
      "kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords",
      "kinesis:ListShards", "kinesis:SubscribeToShard"
    ]
    resources = [local.kinesis_stream_arn]
  }
  statement {
    actions   = ["kinesis:PutRecord", "kinesis:PutRecords"]
    resources = [local.kinesis_anomalies_arn]
  }
  statement {
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [
      local.s3_silver_arn, "${local.s3_silver_arn}/*"
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:*"]
  }
}

resource "aws_iam_role" "flink_app" {
  name               = "${var.project}-flink-app-role"
  assume_role_policy = data.aws_iam_policy_document.flink_trust.json

  tags = { Purpose = "Managed Flink: OHLC + anomaly detection" }
}

resource "aws_iam_role_policy" "flink_app" {
  name   = "${var.project}-flink-app-policy"
  role   = aws_iam_role.flink_app.id
  policy = data.aws_iam_policy_document.flink_permissions.json
}

# =========================================================
# 4. Analyst Read-Only Role (assumed by Identity Center users)
# =========================================================
data "aws_iam_policy_document" "analyst_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
    # In the IP-restriction drill, we add a condition here
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = [var.allowed_admin_ip_cidr]
    }
  }
}

data "aws_iam_policy_document" "analyst_permissions" {
  # Athena queries
  statement {
    actions = [
      "athena:StartQueryExecution", "athena:GetQueryExecution",
      "athena:GetQueryResults", "athena:StopQueryExecution",
      "athena:ListWorkGroups", "athena:GetWorkGroup"
    ]
    resources = ["*"]
  }
  # Read Glue Catalog (Lake Formation will further restrict on Day 19)
  statement {
    actions = [
      "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable",
      "glue:GetTables", "glue:GetPartitions"
    ]
    resources = ["*"]
  }
  # Read Athena results + silver/gold data
  statement {
    actions = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
    resources = [
      local.s3_athena_arn, "${local.s3_athena_arn}/*",
      local.s3_silver_arn, "${local.s3_silver_arn}/*",
      local.s3_gold_arn,   "${local.s3_gold_arn}/*"
    ]
  }
}

resource "aws_iam_role" "analyst_readonly" {
  name               = "${var.project}-analyst-readonly-role"
  assume_role_policy = data.aws_iam_policy_document.analyst_trust.json

  tags = { Purpose = "Read-only analytics access " }
}

resource "aws_iam_role_policy" "analyst_readonly" {
  name   = "${var.project}-analyst-readonly-policy"
  role   = aws_iam_role.analyst_readonly.id
  policy = data.aws_iam_policy_document.analyst_permissions.json
}