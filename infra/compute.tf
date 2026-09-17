resource "aws_ecr_repository" "wallet" { name = "novapay-wallet" }
resource "aws_ecs_cluster" "novapay" { name = "novapay-cluster" }
resource "aws_cloudwatch_log_group" "wallet" {
  name              = "/novapay/wallet"
  retention_in_days = 365
}
resource "aws_iam_role" "task_exec" {
  name = "novapay-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role" "task" {
  name = "novapay-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_ecs_task_definition" "wallet" {
  family                   = "novapay-wallet"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name  = "wallet"
    image = "${aws_ecr_repository.wallet.repository_url}:latest"
    portMappings = [{ containerPort = 8080 }]
    secrets = [{ name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_pass.arn }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.wallet.name
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "wallet"
      }
    }
    readonlyRootFilesystem = true
    user                   = "65532:65532"
  }])
}