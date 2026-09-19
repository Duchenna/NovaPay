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
}

