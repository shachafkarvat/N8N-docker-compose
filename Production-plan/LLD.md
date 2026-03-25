# Taurak N8N – Low-Level Design (LLD)

## ECS Task
- Image: `docker.n8n.io/n8nio/n8n:stable`
- Port: 5678
- EFS mount: `/home/node/.n8n`
- Env:
  - `N8N_HOST=n8n.taurak.co.uk`
  - `N8N_PORT=5678`
  - `N8N_PROTOCOL=https`
  - `WEBHOOK_URL=https://n8n.taurak.co.uk/`
  - `DB_TYPE=postgresdb`
  - `DB_POSTGRESDB_HOST=<RDS_ENDPOINT>`
  - `DB_POSTGRESDB_DATABASE=n8n`
  - `DB_POSTGRESDB_USER=n8n_user`
  - `DB_POSTGRESDB_PASSWORD` (SSM SecureString)
  - `N8N_ENCRYPTION_KEY=<existing>`

## RDS
- Engine: PostgreSQL 16
- Instance: `db.t4g.micro`
- Storage: 20–30GB gp3
- Single-AZ
- Backups enabled

## EFS
- Mount targets in private subnets
- SG allows 2049 from ECS SG

## ALB
- HTTPS only
- ACM cert
- Health check: `GET /` (or `/healthz` if configured)
- Target type: IP (Fargate)

## Route53
- Hosted Zone: `Z773GZMBCOZSA`
- Record: `n8n.taurak.co.uk` → ALB

## Backups
- EventBridge schedule → Fargate task
- `pg_dump` + tar of EFS → S3

## creds.json Sync
- Cron in ECS task (every 5m):
  - hash `creds.json`
  - update SSM SecureString if changed
