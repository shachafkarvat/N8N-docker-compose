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
- S3 bucket: `n8n-taurak-state` (versioning + AES-256 encryption)
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
  --name "/n8n/encryption_key" \
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

The EC2 instance will have a fresh PostgreSQL container started by userdata. Restore to it:

```bash
# 1. Start an SSM session on the instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=n8n-instance" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region eu-west-2)

aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2

# 2. Inside the session: stop n8n (leave postgres running)
docker compose -f /opt/n8n/docker-compose.yml stop n8n

# 3. Copy your backup SQL to the instance via S3
aws s3 cp backups/<timestamp>/postgres.sql s3://n8n-taurak-backups/restore/postgres.sql

# 4. On the instance: download and restore
aws s3 cp s3://n8n-taurak-backups/restore/postgres.sql /tmp/postgres.sql --region eu-west-2
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U n8n_user -d n8n < /tmp/postgres.sql

# 5. Restore n8n data volume (workflows, config)
aws s3 cp backups/<timestamp>/n8n_data.tar.gz s3://n8n-taurak-backups/restore/n8n_data.tar.gz

# On the instance:
aws s3 cp s3://n8n-taurak-backups/restore/n8n_data.tar.gz /tmp/n8n_data.tar.gz --region eu-west-2
docker run --rm \
  -v n8n_n8n_data:/data \
  -v /tmp:/restore \
  alpine sh -c "cd /data && tar xzf /restore/n8n_data.tar.gz"

# 6. Restart n8n
docker compose -f /opt/n8n/docker-compose.yml start n8n
```

### ECS path

```bash
# 1. Upload backup to S3
aws s3 cp backups/<timestamp>/postgres.sql s3://n8n-taurak-backups/restore/postgres.sql
aws s3 cp backups/<timestamp>/n8n_data.tar.gz s3://n8n-taurak-backups/restore/n8n_data.tar.gz

# 2. Restore PostgreSQL to RDS
#    Run from a machine with network access to the RDS endpoint (or a bastion)
RDS_HOST=$(terraform -chdir=Production-plan/terraform-ecs output -raw rds_endpoint | cut -d: -f1)
aws s3 cp s3://n8n-taurak-backups/restore/postgres.sql /tmp/postgres.sql
psql -h "$RDS_HOST" -U n8n_user -d n8n < /tmp/postgres.sql

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
