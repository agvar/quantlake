# =========================================================
# QuantLake lake CMK (customer-managed key)
#
# One symmetric CMK encrypts all five lakehouse buckets via
# SSE-KMS. We rotate it yearly and let IAM identity-based
# policies (in the iam module) delegate Decrypt/GenerateDataKey
# to the Glue / Lambda / Flink roles.
#
# Key-policy strategy: grant the account root kms:* so that
# IAM policies are *allowed to delegate* key usage. This is the
# AWS-recommended default — the key policy opens the door, the
# IAM policies decide who walks through it.
# =========================================================

resource "aws_kms_key" "lake" {
  description             = "${var.project} lakehouse data encryption key"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project}-lake-key"
    Statement = [
      {
        Sid       = "EnableRootAccountDelegation"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = { Module = "kms" }
}

resource "aws_kms_alias" "lake" {
  name          = "alias/${var.project}-lake"
  target_key_id = aws_kms_key.lake.key_id
}
