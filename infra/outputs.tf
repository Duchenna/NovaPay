output "ecr_repo_url" { value = aws_ecr_repository.wallet.repository_url }
output "db_endpoint" { value = aws_db_instance.wallet.endpoint }