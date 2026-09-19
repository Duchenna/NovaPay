# ---------------------------------------------------------------------------
# KMS key — encrypts the Secrets Manager secret for the DB password
# ---------------------------------------------------------------------------
resource "aws_kms_key" "novapay" {
  description             = "NovaPay secrets CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid       = "AllowSecretsManager"
        Effect    = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "novapay-secrets-cmk" }
}

resource "aws_kms_alias" "novapay" {
  name          = "alias/novapay-secrets"
  target_key_id = aws_kms_key.novapay.key_id
}