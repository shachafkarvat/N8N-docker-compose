# DEPRECATED

This directory is superseded. Use one of the two new codebases instead:

| Directory | Architecture | Est. Cost |
|-----------|-------------|-----------|
| `../terraform-ec2/` | EC2 t4g.medium + Docker Compose + Traefik + local PostgreSQL | ~$30/month |
| `../terraform-ecs/` | ECS Fargate + ALB + RDS PostgreSQL + EFS | ~$92/month |

## Why deprecated?

The original Terraform in this directory contained multiple critical bugs:
- S3 bucket names used underscores (invalid — S3 requires hyphens)
- SSM/KMS permissions were on the wrong IAM role (task role instead of execution role)
- SSM parameters were only `data` sources — would fail on first `terraform apply`
- RDS used deprecated `name` attribute and non-specific engine version
- No CloudWatch logging, no HTTP→HTTPS redirect, no S3 hardening
- EFS lacked encryption and access points
- Backup task was designed but never implemented in Terraform
- ECS task was severely undersized (512 CPU / 1 GB RAM)

All issues have been resolved in the new codebases.
