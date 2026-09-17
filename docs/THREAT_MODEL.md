# Threat Model (STRIDE)

Assets: wallet balances (kobo), PII (BVN/NIN), API creds, DB, secrets, CI.

| Threat | Vector | Control |
|---|---|---|
| Spoofing | Stolen token | mTLS, short-lived OIDC tokens |
| Tampering | Modified image | cosign signing, digest pinning |
| Repudiation | No audit trail | JSON logs -> CloudWatch (365d) |
| Info disclosure | Secret in repo/image | gitleaks gate, distroless, KMS |
| DoS | Unbounded queries | ALB rate limit, WAF, DB conn cap |
| Elevation | Over-broad IAM | Per-resource ARNs; no wildcards |

NDPA 2023 / CBN: PII encrypted in transit + at rest; access logged for audit.