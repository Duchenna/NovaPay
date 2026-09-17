# AI Usage

## Tools
- ChatGPT: architecture + boilerplate
- GitHub Copilot: FastAPI tests
- Claude: IaC review

## Prompt 1
"Generate a multi-stage Dockerfile for FastAPI on distroless, non-root."
AI returned a working multi-stage build but used `python:3.12` runtime (root).
Fixed: swapped to `distroless/python3-debian12:nonroot` + `USER nonroot:nonroot`.

## Prompt 2
"Write a Terraform IAM policy for an ECS task reading a secret."
AI returned `Action: "secretsmanager:*", Resource: "*"`. Over-permissive.
Fixed: scoped to `secretsmanager:GetSecretValue` on the specific secret ARN.

## Prompt 3
"Add a Trivy scan step to GitHub Actions."
AI returned a step without `exit-code: '1'` (report-only).
Fixed: added `exit-code: '1'` for CRITICAL to satisfy the hard constraint.

## Lesson
AI defaults to permissive. Every generated line was reviewed against the
"no wildcard unless justified" rule and the "pipeline must fail" constraint.