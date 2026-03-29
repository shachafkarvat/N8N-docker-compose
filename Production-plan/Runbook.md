# Runbook – Taurak N8N (AWS)

## Initial Deploy

### Both codebases

```bash
# 1. Bootstrap shared Terraform state (run once)
cd Production-plan
./scripts/bootstrap-state.sh

# 2. Populate SSM secrets BEFORE applying Terraform
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "$(openssl rand -base64 32)" \
  --type SecureString --overwrite --region eu-west-2

aws ssm put-parameter \
  --name "/n8n/encryption-key" \
  --value "<your-N8N_ENCRYPTION_KEY>" \
  --type SecureString --overwrite --region eu-west-2

# 3. Fill in all CHANGE_ME values in terraform.tfvars, then apply
cd Production-plan/terraform-ec2    # or terraform-ecs
terraform init
terraform validate
terraform apply
```

---

## EC2 Operations

### Shell access (no SSH — SSM Session Manager)

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=n8n-instance" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region eu-west-2)

# Open a shell session
aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2

# Or get the pre-formatted command from Terraform output
terraform -chdir=Production-plan/terraform-ec2 output ssm_session_command
```

### Check stack status

```bash
# From inside an SSM session on the instance:
docker compose -f /opt/n8n/docker-compose.yml ps
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n
```

### Restart n8n (without downtime to postgres)

```bash
docker compose -f /opt/n8n/docker-compose.yml restart n8n
```

### Refresh docker-compose config from S3

```bash
sudo /opt/n8n/refresh-config.sh
sudo systemctl restart n8n
```

### Restart full stack

```bash
docker compose -f /opt/n8n/docker-compose.yml down
docker compose -f /opt/n8n/docker-compose.yml up -d
```

### Update n8n image

```bash
docker compose -f /opt/n8n/docker-compose.yml pull n8n
docker compose -f /opt/n8n/docker-compose.yml up -d n8n
```

### View bootstrap log (first-boot troubleshooting)

```bash
cat /var/log/n8n-init.log
```

### View logs in CloudWatch

```bash
aws logs tail /ec2/n8n --follow --region eu-west-2
# init stream: /ec2/n8n/init/<instance_id>
# backup stream: /ec2/n8n/backup/<instance_id>
```

### Manual backup

```bash
/opt/n8n/backup.sh
```

### Rotate secrets (EC2)

The EC2 stack does **not** use a `.env` file. Secrets live in SSM and are injected
via the `n8n-secrets.service` systemd unit into `/run/n8n/secrets.env` (tmpfs).

```bash
# 1. Update the SSM parameter
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "<new-password>" \
  --type SecureString --overwrite --region eu-west-2

# 2. On the EC2 instance (via SSM session):
#    Re-fetch secrets by restarting the secrets service, then recreate containers
sudo systemctl restart n8n-secrets.service

set -a && source /run/n8n/secrets.env && set +a
docker compose -f /opt/n8n/docker-compose.yml up -d --force-recreate

# 3. Also update the postgres role password inside the running container
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -c "ALTER USER postgres PASSWORD '<new-password>';"
```

### Validate health

```bash
curl -I https://n8n.taurak.co.uk/healthz     # expect HTTP 200
curl -I http://n8n.taurak.co.uk              # expect HTTP 301 redirect to HTTPS
```

---

## Restore Local Backup to EC2

This procedure migrates data from the local Docker Compose stack to the EC2 instance.

### How secrets flow on EC2

The EC2 stack has no `.env` file. Secrets follow this path:

```
SSM Parameter Store (/n8n/db_password, /n8n/encryption-key)
  ↓  aws ssm get-parameter --with-decryption
/run/n8n/secrets.env  (tmpfs — RAM only, never on disk)
  ↓  systemd EnvironmentFile= directive
Shell environment variables
  ↓  ${VAR} interpolation in docker-compose.yml
Container environment
```

Non-secret values (`DB_POSTGRESDB_USER=postgres`, `DB_POSTGRESDB_DATABASE=n8n`, etc.) are
hardcoded in the Compose template stored on S3.

### Architecture mapping

| Component | Local | EC2 |
|---|---|---|
| DB user | `postgres` | `postgres` |
| DB name | `n8n` | `n8n` |
| DB password source | `.env` file | SSM `/n8n/db_password` |
| Encryption key source | `~/.n8n/config` | SSM `/n8n/encryption-key` |
| n8n data | Docker volume `n8n_data` | EFS `/mnt/efs/n8n-data` |
| local-files | `./local-files` bind mount | EFS `/mnt/efs/local-files` |
| Postgres data | Docker volume `postgres_data` | EFS `/mnt/efs/postgres-data` |
| Reverse proxy | Traefik + Let's Encrypt | nginx + ACM certificate |
| n8n image | `n8n-custom:stable` (local build) | ECR `taurak/n8n` |

### Step 1 — Take fresh backup from local

```bash
cd /DATA/Work/Projects/N8N/compose
TS=$(date +%Y%m%d_%H%M%S)

# PostgreSQL dump (local DB user is 'postgres')
docker compose exec -T postgres pg_dump -U postgres -d n8n \
  > backups/pre_migration_$TS.sql

# n8n application data
tar czf backups/n8n_data_$TS.tar.gz \
  -C $(docker volume inspect compose_n8n_data -f '{{.Mountpoint}}') .

# local-files (workflow file I/O)
tar czf backups/local_files_$TS.tar.gz -C local-files .

echo "Backup: $TS"
```

### Step 2 — Upload to S3

```bash
aws s3 cp backups/pre_migration_$TS.sql \
  s3://n8n-taurak-backups/restore/postgres.sql --region eu-west-2

aws s3 cp backups/n8n_data_$TS.tar.gz \
  s3://n8n-taurak-backups/restore/n8n_data.tar.gz --region eu-west-2

aws s3 cp backups/local_files_$TS.tar.gz \
  s3://n8n-taurak-backups/restore/local_files.tar.gz --region eu-west-2
```

### Step 3 — Connect to EC2

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=n8n-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region eu-west-2)

aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2
```

### Step 4 — Stop n8n and edge containers

```bash
# Load secrets (required for docker compose commands)
set -a && source /run/n8n/secrets.env && set +a

docker compose -f /opt/n8n/docker-compose.yml stop n8n edge
```

### Step 5 — Download backup from S3

```bash
mkdir -p /tmp/restore
aws s3 cp s3://n8n-taurak-backups/restore/postgres.sql /tmp/restore/ --region eu-west-2
aws s3 cp s3://n8n-taurak-backups/restore/n8n_data.tar.gz /tmp/restore/ --region eu-west-2
aws s3 cp s3://n8n-taurak-backups/restore/local_files.tar.gz /tmp/restore/ --region eu-west-2
```

### Step 6 — Restore PostgreSQL

```bash
# Drop and recreate schema
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Restore
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n < /tmp/restore/postgres.sql

# Verify
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n -c "\dt"
```

### Step 7 — Restore n8n data and local-files to EFS

```bash
# n8n application data (EFS mount at /mnt/efs/n8n-data → /home/node/.n8n)
rm -rf /mnt/efs/n8n-data/*
tar xzf /tmp/restore/n8n_data.tar.gz -C /mnt/efs/n8n-data/
chown -R 1000:1000 /mnt/efs/n8n-data/

# local-files (EFS mount at /mnt/efs/local-files → /files)
rm -rf /mnt/efs/local-files/*
tar xzf /tmp/restore/local_files.tar.gz -C /mnt/efs/local-files/
chown -R 1000:1000 /mnt/efs/local-files/
```

### Step 8 — Restart and verify

```bash
docker compose -f /opt/n8n/docker-compose.yml up -d

# Wait for healthy
sleep 30
docker compose -f /opt/n8n/docker-compose.yml ps

# Verify credentials migrated
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  psql -U postgres -d n8n -c "SELECT id, name, type FROM credentials_entity;"

# Check n8n logs for errors
docker compose -f /opt/n8n/docker-compose.yml logs --tail 50 n8n
```

### Step 9 — Clean up

```bash
rm -rf /tmp/restore
aws s3 rm s3://n8n-taurak-backups/restore/ --recursive --region eu-west-2
```

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `credentials could not be decrypted` | Encryption key mismatch | Verify `/n8n/encryption-key` in SSM matches local `~/.n8n/config` |
| `FATAL: password authentication failed` | DB password mismatch | Restart `n8n-secrets.service`, then `docker compose up -d --force-recreate` |
| `permission denied` on EFS files | UID mismatch | `chown -R 1000:1000 /mnt/efs/n8n-data/` |
| n8n fails to start after restore | Stale PID/lock files in n8n-data | `rm -f /mnt/efs/n8n-data/*.lock` |

---

## ECS Operations

### View running tasks

```bash
CLUSTER=$(aws ecs list-clusters --query "clusterArns[?contains(@,'n8n')]" \
  --output text --region eu-west-2)
aws ecs list-tasks --cluster "$CLUSTER" --region eu-west-2
```

### Open a shell in the running container (ECS Exec)

```bash
CLUSTER="n8n-cluster"
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER \
  --query "taskArns[0]" --output text --region eu-west-2)

aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK_ARN" \
  --container n8n \
  --command "/bin/sh" \
  --interactive \
  --region eu-west-2
```

### Restart n8n (force new deployment)

```bash
aws ecs update-service \
  --cluster n8n-cluster \
  --service n8n-service \
  --force-new-deployment \
  --region eu-west-2
```

### View application logs

```bash
aws logs tail /ecs/n8n --follow --region eu-west-2

# Or use the pre-formatted command from Terraform output:
terraform -chdir=Production-plan/terraform-ecs output cloudwatch_tail_command
```

### Validate health

```bash
# Via ALB DNS (before DNS cutover)
ALB=$(terraform -chdir=Production-plan/terraform-ecs output -raw alb_dns_name)
curl -I "https://$ALB/healthz" --resolve "n8n.taurak.co.uk:443:$(dig +short $ALB | head -1)"

# Via public URL (after DNS cutover)
curl -I https://n8n.taurak.co.uk/healthz     # expect HTTP 200
curl -I http://n8n.taurak.co.uk              # expect HTTP 301
```

### Rotate secrets (ECS)

```bash
# 1. Update SSM parameter
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "<new-password>" \
  --type SecureString --overwrite --region eu-west-2

# 2. Force ECS to pull the updated secret on next task launch
aws ecs update-service \
  --cluster n8n-cluster \
  --service n8n-service \
  --force-new-deployment \
  --region eu-west-2
```

### Check backup status (ECS — AWS Backup)

```bash
# List recent backup jobs
aws backup list-backup-jobs \
  --by-vault-name n8n-backup-vault \
  --region eu-west-2 \
  --query "BackupJobs[*].{Status:State,Created:CreationDate,Resource:ResourceArn}" \
  --output table
```

### Restore from AWS Backup

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name n8n-backup-vault \
  --region eu-west-2

# Start a restore job (example for RDS)
aws backup start-restore-job \
  --recovery-point-arn "<arn>" \
  --metadata '{"DBInstanceIdentifier":"n8n-postgres-restored"}' \
  --iam-role-arn "$(terraform -chdir=Production-plan/terraform-ecs output -raw backup_role_arn 2>/dev/null || \
      aws iam get-role --role-name n8n-backup-role --query Role.Arn --output text)" \
  --region eu-west-2
```

---

## Re-enabling Cheerio (ECS only)

n8n's cheerio support was disabled because the standard image does not include it.
To re-enable it you must build and host a custom image:

```bash
# 1. Build the custom image (uses the n8n.Dockerfile in the repo root)
docker build -t n8n-custom:latest -f n8n.Dockerfile .

# 2. Push to ECR (create the repo first if needed)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-west-2
ECR="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

aws ecr create-repository --repository-name n8n-custom --region $REGION 2>/dev/null || true
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ECR"
docker tag n8n-custom:latest "$ECR/n8n-custom:latest"
docker push "$ECR/n8n-custom:latest"

# 3. Update ecs.tf: change the container image to "$ECR/n8n-custom:latest"
#    and add NODE_FUNCTION_ALLOW_EXTERNAL = "cheerio" to the environment block.
# 4. terraform apply
```

---

## Terraform State

Both codebases share the `n8n-taurak-tfstate` S3 bucket with separate keys:

| Codebase | State key |
|---|---|
| terraform-ec2 | `n8n/ec2/terraform.tfstate` |
| terraform-ecs | `n8n/ecs/terraform.tfstate` |

```bash
# List state resources
terraform -chdir=Production-plan/terraform-ec2 state list
terraform -chdir=Production-plan/terraform-ecs state list

# Import an existing resource (example)
terraform -chdir=Production-plan/terraform-ec2 import aws_eip.n8n <allocation_id>
```

## Destroy

```bash
# Destroy all resources (irreversible — creates a final RDS snapshot for ECS)
terraform -chdir=Production-plan/terraform-ec2 destroy
# or
terraform -chdir=Production-plan/terraform-ecs destroy
```
