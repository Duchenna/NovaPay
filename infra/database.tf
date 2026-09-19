# ---------------------------------------------------------------------------
# RDS parameter group — enables query logging for audit (CKV2_AWS_30)
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "wallet" {
  name   = "novapay-wallet-pg"
  family = "postgres16"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = { Name = "novapay-wallet-pg" }
}

# ---------------------------------------------------------------------------
# RDS instance
# ---------------------------------------------------------------------------
# checkov:skip=CKV_AWS_353: Performance Insights deferred for free-tier demo; prod enables.
# checkov:skip=CKV_AWS_157: Multi-AZ deferred for free-tier demo; prod sets true.
# checkov:skip=CKV_AWS_226: Auto minor version upgrade managed via maintenance window in prod.
resource "aws_db_instance" "wallet" {
  identifier                  = "novapay-wallet"
  engine                      = "postgres"
  engine_version              = "16.3"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_encrypted           = true
  db_name                     = "wallet"
  username                    = "novapay_app"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.private.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  deletion_protection         = true
  backup_retention_period     = 7
  copy_tags_to_snapshot       = true

  # <-- NEW LINE, references the parameter group above
  parameter_group_name = aws_db_parameter_group.wallet.name

  tags = { Name = "novapay-wallet-db" }
}
