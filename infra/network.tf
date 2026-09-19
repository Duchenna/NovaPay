# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "novapay" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "novapay-vpc" }
}

# ---------------------------------------------------------------------------
# Private subnets (two AZs — required for RDS subnet group)
# ---------------------------------------------------------------------------
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.10.0/24"
  availability_zone = "eu-west-1a"

  tags = { Name = "novapay-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.11.0/24"
  availability_zone = "eu-west-1b"

  tags = { Name = "novapay-private-b" }
}

# ---------------------------------------------------------------------------
# Security group: ALB (public ingress on 80/443)
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "novapay-alb-sg"
  description = "Public ingress for the NovaPay ALB"
  vpc_id      = aws_vpc.novapay.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere (redirect to HTTPS at the listener)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to the wallet service only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.svc.id]
  }

  tags = { Name = "novapay-alb-sg" }
}

# ---------------------------------------------------------------------------
# Security group: wallet service (ingress only from ALB)
# ---------------------------------------------------------------------------
resource "aws_security_group" "svc" {
  name        = "novapay-svc-sg"
  description = "Wallet service — ingress from ALB only"
  vpc_id      = aws_vpc.novapay.id

  ingress {
    description     = "App port from the ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "HTTPS out to AWS APIs (Secrets Manager, ECR, CloudWatch)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Postgres to the DB security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
  }

  tags = { Name = "novapay-svc-sg" }
}

# ---------------------------------------------------------------------------
# Security group: RDS Postgres (ingress only from wallet service)
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "novapay-db-sg"
  description = "RDS Postgres — ingress from wallet service only"
  vpc_id      = aws_vpc.novapay.id

  ingress {
    description     = "Postgres from the wallet service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.svc.id]
  }

  egress {
    description = "No outbound required"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "novapay-db-sg" }
}

# ---------------------------------------------------------------------------
# DB subnet group (must span at least two AZs)
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "private" {
  name       = "novapay-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "novapay-db-subnets" }
}

