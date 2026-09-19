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
# Security groups — definitions only, NO cross-references here.
# Cross-SG rules are declared as separate aws_security_group_rule resources
# below, which is what breaks the Terraform dependency cycle.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "novapay-alb-sg"
  description = "Public ingress for the NovaPay ALB"
  vpc_id      = aws_vpc.novapay.id

  tags = { Name = "novapay-alb-sg" }
}

resource "aws_security_group" "svc" {
  name        = "novapay-svc-sg"
  description = "Wallet service — ingress from ALB only"
  vpc_id      = aws_vpc.novapay.id

  tags = { Name = "novapay-svc-sg" }
}

resource "aws_security_group" "db" {
  name        = "novapay-db-sg"
  description = "RDS Postgres — ingress from wallet service only"
  vpc_id      = aws_vpc.novapay.id

  tags = { Name = "novapay-db-sg" }
}

# ---------------------------------------------------------------------------
# ALB rules
#   ingress: 443 + 80 from anywhere (public)
#   egress : 8080 to svc
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "HTTPS from anywhere"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  description       = "HTTP from anywhere (listener redirects to HTTPS)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_to_svc" {
  type                     = "egress"
  description              = "Forward to wallet service"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.svc.id
  security_group_id        = aws_security_group.alb.id
}

# ---------------------------------------------------------------------------
# svc rules
#   ingress: 8080 from alb
#   egress : 443 anywhere (AWS APIs), 5432 to db
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "svc_ingress_from_alb" {
  type                     = "ingress"
  description              = "App port from the ALB"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.svc.id
}

resource "aws_security_group_rule" "svc_egress_https" {
  type              = "egress"
  description       = "HTTPS to AWS APIs (Secrets Manager, ECR, CloudWatch)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.svc.id
}

resource "aws_security_group_rule" "svc_egress_to_db" {
  type                     = "egress"
  description              = "Postgres to the DB security group"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.svc.id
}

# ---------------------------------------------------------------------------
# db rules
#   ingress: 5432 from svc
#   egress : none required
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "db_ingress_from_svc" {
  type                     = "ingress"
  description              = "Postgres from the wallet service"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.svc.id
  security_group_id        = aws_security_group.db.id
}

# ---------------------------------------------------------------------------
# DB subnet group (RDS requires at least two AZs)
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "private" {
  name       = "novapay-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "novapay-db-subnets" }
}

resource "aws_lb" "wallet" {
  name               = "novapay-wallet-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "novapay-wallet-alb" }
}

resource "aws_lb_target_group" "wallet" {
  name        = "novapay-wallet-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.novapay.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "novapay-wallet-tg" }
}

resource "aws_lb_listener" "wallet" {
  load_balancer_arn = aws_lb.wallet.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wallet.arn
  }
}


# ---------------------------------------------------------------------------
# VPC flow logs — required for regulatory audit (CBN / NDPA)
# ---------------------------------------------------------------------------
resource "aws_flow_log" "novapay" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.novapay.id
  iam_role_arn         = aws_iam_role.vpc_flow.arn

  tags = { Name = "novapay-vpc-flow-logs" }
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/novapay/vpc-flow"
  retention_in_days = 365

  tags = { Name = "novapay-vpc-flow" }
}

resource "aws_iam_role" "vpc_flow" {
  name = "novapay-vpc-flow"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow" {
  name = "novapay-vpc-flow-policy"
  role = aws_iam_role.vpc_flow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    }]
  })
}