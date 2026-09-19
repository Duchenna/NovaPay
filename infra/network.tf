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
# Default security group — adopted and neutralised (denies all traffic).
# AWS creates one per VPC automatically; this resource strips all rules.
# ---------------------------------------------------------------------------
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.novapay.id

  tags = { Name = "novapay-default-sg-DO-NOT-USE" }
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
# Security groups — definitions only. Cross-SG rules live below as
# aws_security_group_rule resources, which breaks the dependency cycle.
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

# checkov:skip=CKV_AWS_260: HTTP:80 ingress only serves a 301 redirect to HTTPS; no plaintext data traverses it.
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
# DB subnet group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "private" {
  name       = "novapay-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "novapay-db-subnets" }
}

# ---------------------------------------------------------------------------
# ALB, target group, listeners
# ---------------------------------------------------------------------------
resource "aws_lb" "wallet" {
  name               = "novapay-wallet-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  enable_deletion_protection = true
  drop_invalid_header_fields = true

  # <-- NEW
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "wallet-alb"
    enabled = true
  }

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

resource "aws_lb_listener" "wallet_http_redirect" {
  load_balancer_arn = aws_lb.wallet.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "wallet_https" {
  load_balancer_arn = aws_lb.wallet.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.wallet.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wallet.arn
  }
}

# ---------------------------------------------------------------------------
# ACM certificate for the HTTPS listener (valid-but-unapplied demo cert)
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "wallet" {
  domain_name       = "wallet.novapay.example.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "novapay-wallet-cert" }
}

# ---------------------------------------------------------------------------
# WAF — regional WebACL protecting the ALB (rate limit + common managed rules)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# WAF — regional WebACL protecting the ALB
#   * rate limit per IP
#   * AWS Managed Rule Set: KnownBadInputs (Log4Shell and friends)
#   * logging to CloudWatch
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-novapay"
  kms_key_id        = aws_kms_key.novapay.arn
  retention_in_days = 365

  tags = { Name = "novapay-waf-logs" }
}

resource "aws_wafv2_web_acl" "wallet" {
  name        = "novapay-wallet-waf"
  description = "Regional WAF for the NovaPay wallet ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1 — rate limit per IP
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2 — AWS Managed Rule Set: KnownBadInputs (Log4Shell, SSRF, etc.)
  rule {
    name     = "aws-known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3 — AWS Managed Rule Set: Common Rule Set (OWASP-style baseline)
  rule {
    name     = "aws-common"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "novapay-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "novapay-wallet-waf" }
}

# WAF logging → CloudWatch
resource "aws_wafv2_web_acl_logging_configuration" "wallet" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.wallet.arn

  # Redact sensitive headers/cookies so PII doesn't leak into logs (NDPA)
  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
}

# Attach WAF to the ALB
resource "aws_wafv2_web_acl_association" "wallet" {
  resource_arn = aws_lb.wallet.arn
  web_acl_arn  = aws_wafv2_web_acl.wallet.arn
}
# ---------------------------------------------------------------------------
# VPC flow logs — required for regulatory audit (CBN / NDPA)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/novapay/vpc-flow"
  kms_key_id        = aws_kms_key.novapay.arn
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

resource "aws_flow_log" "novapay" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.novapay.id
  iam_role_arn         = aws_iam_role.vpc_flow.arn

  tags = { Name = "novapay-vpc-flow-logs" }
}


# ---------------------------------------------------------------------------
# S3 bucket for ALB access logs (encrypted, private, 90-day lifecycle)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "novapay-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "novapay-alb-logs" }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.novapay.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration { days = 90 }
  }
}
