
# NovaPay Platform Pipeline & Hardening

Wallet microservice for the fictional FirstBank NovaPay super-app. This repo
demonstrates containerization, CI/CD with hard security gates, IaC, secrets
management, and observability.

## Architecture
ALB -> ECS Fargate (wallet, non-root, read-only FS) -> RDS Postgres (private).
Secrets from AWS Secrets Manager (KMS-encrypted, 30-day rotation).
Logs -> CloudWatch (365d). Metrics -> Prometheus (/metrics).

## Real vs simulated
- IaC targets real AWS free-tier. Validated with `terraform validate` + `terraform plan`.
- Local deploy via docker-compose is fully runnable.
- No live traffic; wallet data is stubbed.

## Run locally
    docker compose up --build
    curl localhost:8080/health
    open http://localhost:9090   # Prometheus

## Apply IaC
    cd infra && terraform init && terraform plan

## Non-root proof
    docker run --rm novapay:local id       # uid=65532(nonroot)
    docker inspect --format '{{.Config.User}}' novapay:local

## Wildcard IAM justification
Only `ecr:GetAuthorizationToken` uses Resource="*" (AWS account-scoped; required by AWS).

## Assumptions
- Region eu-west-1 chosen for data-residency demo. Swap to af-south-1 for Nigeria-adjacent.
- Money stored in kobo (integer). KYC tiers modeled on BVN/NIN.

See docs/ for THREAT_MODEL.md, RUNBOOK.md, DATA_RESIDENCY.md, and AI_USAGE.md.