# -----------------------------------------------------------------------------
# Package each producer's handler.py into its own zip on every plan/apply.
# archive_file is a data source -- Terraform recomputes the hash whenever the
# source file changes, so editing handler.py triggers a Lambda redeploy.
# -----------------------------------------------------------------------------
data "archive_file" "batch_zip" {
  type        = "zip"
  source_dir  = "${var.producers_src_root}/batch_lambda"
  output_path = "${path.module}/.build/batch_lambda.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

data "archive_file" "news_zip" {
  type        = "zip"
  source_dir  = "${var.producers_src_root}/news_lambda"
  output_path = "${path.module}/.build/news_lambda.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

# -----------------------------------------------------------------------------
# Batch fetcher (Alpha Vantage daily bars)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "batch" {
  function_name    = "${var.project}-batch-fetcher"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  architectures    = ["arm64"]
  kms_key_arn      = var.cmk_arn
  filename         = data.archive_file.batch_zip.output_path
  source_code_hash = data.archive_file.batch_zip.output_base64sha256

  # 5 tickers x ~14s/each = ~70s; allow headroom for retries.
  timeout     = 180
  memory_size = 256

  environment {
    variables = {
      RAW_BUCKET = var.raw_bucket
      SECRET_ID  = var.secret_id
      TICKERS    = var.tickers
    }
  }

  tags = { Module = "producers", Producer = "batch" }
}

resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/lambda/${aws_lambda_function.batch.function_name}"
  retention_in_days = 14
  tags              = { Module = "producers" }
}

# -----------------------------------------------------------------------------
# News fetcher (Finnhub company-news)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "news" {
  function_name    = "${var.project}-news-fetcher"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  architectures    = ["arm64"]
  kms_key_arn      = var.cmk_arn
  filename         = data.archive_file.news_zip.output_path
  source_code_hash = data.archive_file.news_zip.output_base64sha256

  # Finnhub is faster (1.1s sleep). 5 tickers x ~2s = ~10s; pad for retries.
  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      RAW_BUCKET = var.raw_bucket
      SECRET_ID  = var.secret_id
      TICKERS    = var.tickers
    }
  }

  tags = { Module = "producers", Producer = "news" }
}

resource "aws_cloudwatch_log_group" "news" {
  name              = "/aws/lambda/${aws_lambda_function.news.function_name}"
  retention_in_days = 14
  tags              = { Module = "producers" }
}

# -----------------------------------------------------------------------------
# EventBridge Scheduler -- one schedule per Lambda
# -----------------------------------------------------------------------------
# A dedicated role for Scheduler to invoke our Lambdas. We keep this separate
# from the Lambda execution role: Scheduler is the *caller*, Lambda is the
# *callee*. Two different responsibilities, two different roles.
data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.batch.arn,
      aws_lambda_function.news.arn,
    ]
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project}-scheduler-invoke-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
  tags               = { Module = "producers" }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${var.project}-scheduler-invoke-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule_group" "producers" {
  name = "${var.project}-producers"
}

# Daily at 21:30 UTC -- after US equity market close (16:00 ET = 20:00 UTC in
# DST, 21:00 UTC in standard time). 21:30 is comfortably after either close.
resource "aws_scheduler_schedule" "batch_daily" {
  name        = "${var.project}-batch-daily"
  group_name  = aws_scheduler_schedule_group.producers.name
  description = "Pull Alpha Vantage daily bars after US market close"

  flexible_time_window { mode = "OFF" } # fire at the exact time

  schedule_expression          = "cron(30 21 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.batch.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Hourly during US market hours (14:00-21:00 UTC ~ 9 AM-4 PM ET in DST).
# News doesn't stop after close so we run a couple extra hours into the evening.
resource "aws_scheduler_schedule" "news_hourly" {
  name        = "${var.project}-news-hourly"
  group_name  = aws_scheduler_schedule_group.producers.name
  description = "Pull Finnhub company-news during and around US market hours"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = "cron(0 13-22 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.news.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
