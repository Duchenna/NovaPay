# Data Residency

Demo pins resources to eu-west-1. For a Nigerian regulated institution,
swap to af-south-1 (Cape Town) as the nearest AWS region, or a licensed
in-country provider. RDS snapshots, CloudWatch logs, and KMS keys must
all reside in the chosen region. Cross-region replication requires
explicit compliance sign-off.