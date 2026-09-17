# Runbook: Unauthorized Access

## Detect
- Alert `WalletErrorRateHigh` OR anomalous `secretsmanager:GetSecretValue` OR console login anomaly.

## Contain (T+5)
    aws secretsmanager rotate-secret --secret-id novapay/wallet/db-password --force
    aws ecs update-service --cluster novapay-cluster --service wallet --desired-count 0
    aws iam update-access-key --access-key-id <ID> --status Inactive

## Eradicate (T+15)
- Roll new task definition with rotated secret ARN.
- Re-deploy from last known-good signed image digest.

## Recover (T+30)
- Scale back up. Verify /ready=200 and wallet_requests_total{status="200"} climbing.

## Review (T+60)
- CloudTrail for actor; identify vector; open post-incident ticket.
- Purge secret from git history if committed; add gitleaks rule.

## Comms
- Notify Head of Security + DPO. NDPA breach notification within 72h if PII affected.