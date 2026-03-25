# Taurak N8N – High-Level Design (HLD)

## Objectives
- Deploy n8n on AWS ECS Fargate in `eu-west-2`
- Use RDS PostgreSQL (single-AZ, low-cost)
- Use EFS for persistent n8n storage (`/home/node/.n8n`)
- Expose via ALB + ACM certificate + Route53
- Backups to S3 with defined retention

## Key Decisions
- **ALB (not Traefik)** for HTTPS + webhooks
- **RDS** for database
- **EFS** for `creds.json` and local n8n state
- **Terraform** with S3 backend + DynamoDB locking

## Architecture Summary
- VPC (existing): `<VPC_ID>`
- Public subnets: ALB
- Private subnets: ECS, RDS, EFS
- Route53 zone: `Z773GZMBCOZSA`
- ACM certificate for `n8n.taurak.co.uk`

## Security
- ALB: inbound 443 from 0.0.0.0/0
- ECS: inbound 5678 from ALB SG only
- RDS: inbound 5432 from ECS SG only
- EFS: inbound 2049 from ECS SG only
- No SSH or public DB access

## Availability & Scaling
- Single-AZ (cost optimized)
- ECS service can scale vertically or horizontally later

## Backups
- Daily @ 03:00 (retain 7)
- Weekly Sunday (retain 4)
- Monthly last Sunday (retain 12)

## Migration
- Dump current Postgres
- Restore to RDS
- Copy `/home/node/.n8n` to EFS
- Validate workflows and credentials
