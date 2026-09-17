resource "aws_kms_key" "novapay" { description = "NovaPay secrets CMK" }
resource "aws_secretsmanager_secret" "db_pass" {
  name                    = "novapay/wallet/db-password"
  recovery_window_in_days = 7
  kms_key_id              = aws_kms_key.novapay.arn
}