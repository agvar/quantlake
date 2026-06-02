# =========================================================
# QuantLake S3 lakehouse — five buckets
#
#   raw            landing zone, immutable source-of-truth
#   bronze         cleaned/typed, still close to source
#   silver         conformed, joined, deduped
#   gold           business-level aggregates for BI
#   athena-results query output spill (transient)
#
# Every bucket gets: versioning, SSE-KMS + S3 Bucket Key,
# full Block Public Access, and a lifecycle policy.
#
# We drive all five from one map so the common config is
# written once; each zone carries its own lifecycle rules.
# =========================================================

locals {
  # Per-zone lifecycle intent.
  #   transitions       : age-based class moves for CURRENT objects
  #   expire_current    : delete current objects after N days (0 = never)
  #   noncurrent_expire : delete old versions after N days
  buckets = {
    raw = {
      transitions       = [
        { days = 30, class = "STANDARD_IA" },
        { days = 90, class = "GLACIER_IR" },
      ]
      expire_current    = 0
      noncurrent_expire = 7
    }
    bronze = {
      transitions       = []
      expire_current    = 0
      noncurrent_expire = 14
    }
    silver = {
      transitions       = []
      expire_current    = 0
      noncurrent_expire = 14
    }
    gold = {
      transitions       = []
      expire_current    = 0
      noncurrent_expire = 30
    }
    "athena-results" = {
      transitions       = []
      expire_current    = 7   # query spill is disposable
      noncurrent_expire = 1
    }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = "${var.project}-${each.key}-${var.account_id}"

  tags = {
    Module = "s3-lake"
    Zone   = each.key
  }
}

# --- Versioning -------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Encryption: SSE-KMS + S3 Bucket Key ------------------------
# bucket_key_enabled = true is the ~99% KMS-call reducer.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# --- Block Public Access (all four switches) --------------------
resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Lifecycle --------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.this[each.key].id

  # Lifecycle depends on versioning being active first.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "${each.key}-lifecycle"
    status = "Enabled"

    filter {} # whole-bucket

    dynamic "transition" {
      for_each = each.value.transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.class
      }
    }

    dynamic "expiration" {
      for_each = each.value.expire_current > 0 ? [1] : []
      content {
        days = each.value.expire_current
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = each.value.noncurrent_expire
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
