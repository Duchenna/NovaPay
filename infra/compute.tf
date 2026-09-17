# ---------------------------------------------------------------------------
# ECR — where CI pushes the built wallet image
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "wallet" {
  name                 = "novapay-wallet"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# ---------------------------------------------------------------------------
# ECS cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "novapay" {
  name = "novapay-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch log group (referenced by the task definition)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "wallet" {
  name              = "/novapay/wallet"
  retention_in_days = 365
}

# ---------------------------------------------------------------------------
# IAM — task execution role (pull image, write logs, read secrets at start)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task_exec" {
  name = "novapay-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


# ---------------------------------------------------------------------------
# IAM — task role (app identity: only read its own secret)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name = "novapay-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


# ---------------------------------------------------------------------------
# ECS task definition — bootstrapped by Terraform, continuously updated by CI
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "wallet" {
  family                   = "novapay-wallet"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "wallet"
    image        = "${aws_ecr_repository.wallet.repository_url}:${var.image_tag}"
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    secrets = [{
      name      = "DB_PASSWORD"
      valueFrom = aws_secretsmanager_secret.db_pass.arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.wallet.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "wallet"
      }
    }

    readonlyRootFilesystem = true
    user                   = "65532:65532" # distroless nonroot

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/health')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])
}

# ---------------------------------------------------------------------------
# ECS service — the deploy target CI updates on every merge to main
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "wallet" {
  name            = "wallet"
  cluster         = aws_ecs_cluster.novapay.id
  task_definition = aws_ecs_task_definition.wallet.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.svc.id]
    assign_public_ip = false
  }

  # Zero-downtime rolling deploy + automatic rollback on failure
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Wait for the service to stabilise before Terraform considers the apply done
  wait_for_steady_state = true

  # CI owns the task definition after bootstrap — Terraform must not fight it.
  # Without this, every `terraform apply` would revert the image tag CI just deployed.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_iam_role_policy.task_exec,
    aws_iam_role_policy.task,
  ]
}