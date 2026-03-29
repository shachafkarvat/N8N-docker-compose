# Migration Plan – Taurak N8N to AWS

## Choosing a deployment target

Two Terraform codebases are available. Pick **one** before starting:

| | `terraform-ec2/` | `terraform-ecs/` |
|---|---|---|
| Cost | ~$30/month | ~$92/month |
| Compute | EC2 t4g.medium + Docker Compose | ECS Fargate 1 vCPU / 4 GB |
| Database | PostgreSQL in container (EBS) | RDS db.t4g.micro (managed) |
| TLS | Traefik + Let's Encrypt | ACM + ALB |
| Ops access | SSM Session Manager | ECS Exec |

Both paths follow the same phase structure. Differences are noted inline.

---

## Phase 0 – Prepare

1. Record current n8n version:
   ```bash
   docker exec n8n n8n --version
   ```
2. Record your `N8N_ENCRYPTION_KEY` from the local `.env` file — you will need it in Phase 2.
3. Reduce Route53 TTL for `n8n.taurak.co.uk` to **60 seconds** now, so DNS cutover in Phase 4 is fast.

---

## Phase 1 – Backup (local)

1. Run the existing backup script:
   ```bash
   ./backup.sh
   ```
2. Verify the backup artifacts:
   ```bash
   # Check the SQL dump is readable
   pg_restore --list backups/<timestamp>/postgres.sql 2>/dev/null | head -20
   # Or for plain SQL:
   head -20 backups/<timestamp>/postgres.sql

   # Verify the data archive
   tar -tf backups/<timestamp>/n8n_data.tar.gz | head -20
   ```
3. Note the backup directory path — you will use it in Phase 3.

---

## Phase 2 – Provision AWS

### 2a. Bootstrap Terraform state bucket

Run once — creates the S3 bucket and DynamoDB lock table used by both codebases:

```bash
cd Production-plan
./scripts/bootstrap-state.sh
```

The script creates:
- S3 bucket: `n8n-taurak-tfstate` (versioning + AES-256 encryption)
- DynamoDB table: `n8n-taurak-state-lock`

### 2b. Populate SSM SecureString parameters

Terraform creates the SSM parameters with placeholder values. **Update them before `terraform apply`** so the instance/task can fetch real secrets at boot:

```bash
# DB password — use a strong random value
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "$(openssl rand -base64 32)" \
  --type SecureString \
  --overwrite \
  --region eu-west-2

# n8n encryption key — use the value from your local .env (N8N_ENCRYPTION_KEY)
aws ssm put-parameter \
  --name "/n8n/encryption-key" \
  --value "<your-existing-N8N_ENCRYPTION_KEY>" \
  --type SecureString \
  --overwrite \
  --region eu-west-2
```

> **Important**: use the **same** `N8N_ENCRYPTION_KEY` as your local install.
> If you change it, n8n cannot decrypt stored credentials.

### 2c. Fill in terraform.tfvars

Edit `terraform.tfvars` in your chosen codebase and replace every `CHANGE_ME` placeholder:

```bash
# Find your VPC and subnets
aws ec2 describe-vpcs --region eu-west-2
aws ec2 describe-subnets --region eu-west-2

# EC2 only:
# public_subnet_id  — one public subnet (internet gateway route required)
# ssl_email         — your email address for Let's Encrypt

# ECS only:
# public_subnet_ids  — two public subnets in different AZs (for ALB)
# private_subnet_ids — two private subnets with NAT GW routes (for Fargate tasks)
# nat_gateway_id     — existing NAT gateway ID
```

### 2d. Apply Terraform

```bash
cd Production-plan/terraform-ec2    # or terraform-ecs
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Phase 3 – Restore Data

### EC2 path

The EC2 instance runs PostgreSQL and n8n via Docker Compose, with all persistent data on EFS.
The local stack uses the `postgres` superuser — the EC2 template is aligned to use the same role.
Credentials are encrypted in PostgreSQL with `N8N_ENCRYPTION_KEY` (stored in SSM) — as long as the key matches the local install, credentials will decrypt correctly after restore.

#### Prerequisites

- AWS CLI v2 configured with appropriate permissions
- `session-manager-plugin` installed locally (`aws ssm start-session` requires it)
- A fresh backup from the local stack (Phase 1)

#### Step 1 — Take a fresh backup from the local stack

```bash
cd /DATA/Work/Projects/N8N/compose

# Dump PostgreSQL (local DB user is 'postgres', database is 'n8n')
docker compose exec -T postgres pg_dump -U postgres -d n8n \
  > backups/pre_migration_$(date +%Y%m%d_%H%M%S).sql

# Archive n8n application data (encryption key config, custom nodes, etc.)
tar czf backups/n8n_data_$(date +%Y%m%d_%H%M%S).tar.gz \
  -C $(docker volume inspect compose_n8n_data -f '{{.Mountpoint}}') .

# Archive local-files (workflow file I/O directory)
tar czf backups/local_files_$(date +%Y%m%d_%H%M%S).tar.gz -C local-files .
```

#### Step 2 — Upload backup artifacts to S3

```bash
# Upload all three artifacts
aws s3 cp backups/pre_migration_*.sql \
  s3://n8n-taurak-backups/restore/postgres.sql --region eu-west-2

aws s3 cp backups/n8n_data_*.tar.gz \
  s3://n8n-taurak-backups/restore/n8n_data.tar.gz --region eu-west-2

aws s3 cp backups/local_files_*.tar.gz \
  s3://n8n-taurak-backups/restore/local_files.tar.gz --region eu-west-2
```

#### Step 3 — Connect to the EC2 instance via SSM

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=n8n-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region eu-west-2)

aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2
```

#### Step 4 — Stop n8n and edge (leave postgres running)

```bash
# Load secrets into shell env (required for docker compose commands)
set -a && source /run/n8n/secrets.env && set +a

docker compose -f /opt/n8n/docker-compose.yml stop n8n edge
```

#### Step 5 — Download backup from S3

```bash
mkdir -p /tmp/restore
aws s3 cp s3://n8n-taurak-backups/restore/postgres.sql /tmp/restore/ --region eu-west-2
aws s3 cp s3://n8n-taurak-backups/restore/n8n_data.tar.gz /tmp/restore/ --region eu-west-2
aws s3 cp s3://n8n-taurak-backups/restore/local_files.tar.gz /tmp/restore/ --region eu-west-2
```

#### Step 6 — Restore PostgreSQL

```bash
# Drop and recreate the public schema to start clean
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Restore the dump
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n < /tmp/restore/postgres.sql

# Verify tables exist
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n -c "\dt"
```

#### Step 7 — Restore n8n application data to EFS

```bash
# The n8n-data EFS mount is at /mnt/efs/n8n-data (maps to /home/node/.n8n)
# Clear existing data and extract backup
rm -rf /mnt/efs/n8n-data/*
tar xzf /tmp/restore/n8n_data.tar.gz -C /mnt/efs/n8n-data/

# Fix ownership (EFS access point enforces UID 1000, but verify)
chown -R 1000:1000 /mnt/efs/n8n-data/
```

#### Step 8 — Restore local-files to EFS

```bash
# The local-files EFS mount is at /mnt/efs/local-files (maps to /files)
rm -rf /mnt/efs/local-files/*
tar xzf /tmp/restore/local_files.tar.gz -C /mnt/efs/local-files/
chown -R 1000:1000 /mnt/efs/local-files/
```

#### Step 9 — Restart the stack

```bash
docker compose -f /opt/n8n/docker-compose.yml up -d

# Wait for healthy
docker compose -f /opt/n8n/docker-compose.yml ps

# Check n8n logs
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n
```

#### Step 10 — Clean up

```bash
rm -rf /tmp/restore
```

### ECS path

> **Note**: The ECS path uses RDS (managed PostgreSQL) instead of a container.
> The DB user for RDS is also `postgres` to match the local dump.

```bash
# 1. Upload backup to S3
aws s3 cp backups/<timestamp>/postgres.sql s3://n8n-taurak-backups/restore/postgres.sql
aws s3 cp backups/<timestamp>/n8n_data.tar.gz s3://n8n-taurak-backups/restore/n8n_data.tar.gz

# 2. Restore PostgreSQL to RDS
#    Run from a machine with network access to the RDS endpoint (or a bastion)
RDS_HOST=$(terraform -chdir=Production-plan/terraform-ecs output -raw rds_endpoint | cut -d: -f1)
aws s3 cp s3://n8n-taurak-backups/restore/postgres.sql /tmp/postgres.sql
psql -h "$RDS_HOST" -U postgres -d n8n < /tmp/postgres.sql

# 3. Copy n8n data to EFS
#    Spin up a temporary EC2 (or Fargate task) that mounts the EFS access point
#    and extract the tar archive:
EFS_ID=$(terraform -chdir=Production-plan/terraform-ecs output -raw efs_id)
AP_ID=$(terraform -chdir=Production-plan/terraform-ecs output -raw efs_access_point_id)

# Mount the EFS from a temporary EC2 in the same VPC:
sudo mount -t efs -o tls,accesspoint=$AP_ID $EFS_ID /mnt/efs

aws s3 cp s3://n8n-taurak-backups/restore/n8n_data.tar.gz /tmp/n8n_data.tar.gz
tar xzf /tmp/n8n_data.tar.gz -C /mnt/efs
sudo umount /mnt/efs
```

---

## Phase 4 – Cutover

1. Verify the new deployment is healthy before touching DNS:
   ```bash
   # EC2
   curl -I https://n8n.taurak.co.uk/healthz   # expect 200 (from new instance)

   # ECS
   ALB=$(terraform -chdir=Production-plan/terraform-ecs output -raw alb_dns_name)
   curl -I "https://$ALB/healthz"              # expect 200
   ```

2. Update Route53 DNS (both codebases do this automatically via Terraform — the record is already applied).
   Because you lowered the TTL to 60 s in Phase 0, propagation completes within ~2 minutes.

3. Verify the public URL resolves to the new endpoint:
   ```bash
   dig +short n8n.taurak.co.uk
   curl -I https://n8n.taurak.co.uk/healthz
   curl -I http://n8n.taurak.co.uk            # expect 301 redirect to HTTPS
   ```

---

## Phase 5 – Verify

1. Log in to `https://n8n.taurak.co.uk`
2. Confirm workflows and credentials are intact
3. Execute a test workflow
4. Check logs for errors:
   ```bash
   # EC2
   aws logs tail /ec2/n8n --follow --region eu-west-2

   # ECS
   aws logs tail /ecs/n8n --follow --region eu-west-2
   ```

---

## Phase 6 – Enable Ops

1. **EC2**: Backup cron is active from first boot (daily 03:00 UTC).
   Verify the first run:
   ```bash
   aws s3 ls s3://n8n-taurak-backups/daily/ --region eu-west-2
   ```

2. **ECS**: AWS Backup is active from first apply.
   Check vault in the AWS console: *AWS Backup → Backup vaults → n8n-backup-vault*

3. Restore Route53 TTL to 300 s (or your preferred value):
   ```bash
   # The Terraform-managed record uses TTL 60 — update terraform.tfvars or
   # edit the record directly in Route53 console if desired.
   ```
