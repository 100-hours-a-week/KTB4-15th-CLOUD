# Prod V3 shared database access

Prod V3 reuses the existing Single-AZ Prod V2 RDS instances and the existing
`lookddak` MySQL/PostgreSQL databases. This module does not create a database,
schema, table, or RDS instance.

It adds only:

- EKS Cluster SG access to the existing MySQL 3306 and PostgreSQL 5432 ports
- Prod V3 connection metadata under `/lookddak/prod/v3`
- separate Prod V3 login roles that inherit the existing V2 database privileges
- an idempotent SSM bootstrap document that creates or verifies credentials

## Bootstrap

After Terraform apply, run the command exposed by:

```bash
terraform output -raw prod_v3_database_bootstrap_command
```

Then inspect the command without exposing credentials:

```bash
aws ssm get-command-invocation \
  --region ap-northeast-2 \
  --command-id <command-id> \
  --instance-id <instance-id> \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json
```

The Runbook reuses a working SecureString password. It rotates a password only
when the parameter is missing, too short, or no longer authenticates.

## Boundaries

- RDS remains Single-AZ.
- Existing V2 users, data, queues, and buckets are not changed.
- MySQL privileges are restricted to the same database-scoped DML and DDL set
  used by the existing V2 app account because the current BE prod profile uses
  `ddl-auto: update`. Global and `DROP` privileges are not granted.
- PostgreSQL V3 roles inherit the existing V2 app/migration roles so current and
  future object grants stay aligned without changing table ownership.
