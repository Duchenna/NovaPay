resource "aws_vpc" "novapay" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "novapay-vpc" }
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.10.0/24"
  availability_zone = "eu-west-1a"
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.11.0/24"
  availability_zone = "eu-west-1b"
}
resource "aws_security_group" "alb" { 
  name   = "novapay-alb-sg"
  vpc_id = aws_vpc.novapay.id
  ingress { 
    from_port       = 8080 
    to_port         = 8080 
    protocol        = "tcp" 
    security_groups = [aws_security_group.alb.id] 
  }

  egress  { 
    from_port   = 443  
    to_port     = 443  
    protocol    = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

resource "aws_security_group" "db"  {
  name       = "novapay-db-sg"
  vpc_id = aws_vpc.novapay.id
}

resource "aws_db_subnet_group" "private" {
  name       = "novapay-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "novapay-db-subnet-group"
  }
}

resource "aws_iam_role_policy" "task" {
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_pass.arn
    }]
  })
}

resource "aws_iam_role_policy" "task_exec" {
  role = aws_iam_role.task_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*" },   # JUSTIFIED: account-scoped, AWS-defined, no narrower ARN exists
      { Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage"]
        Resource = aws_ecr_repository.wallet.arn },
      { Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.wallet.arn}:*" },
      { Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_pass.arn }
    ]
  })
}
