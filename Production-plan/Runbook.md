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
  --name "/n8n/encryption_key" \
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

```bash
# 1. Update SSM parameter
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "<new-password>" \
  --type SecureString --overwrite --region eu-west-2

# 2. Re-write .env from SSM (re-run the relevant parts of userdata, or manually)
DB_PASS=$(aws ssm get-parameter --name /n8n/db_password \
  --with-decryption --query Parameter.Value --output text --region eu-west-2)

# Update .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$DB_PASS/" /opt/n8n/.env
sed -i "s/^DB_POSTGRESDB_PASSWORD=.*/DB_POSTGRESDB_PASSWORD=$DB_PASS/" /opt/n8n/.env
chmod 600 /opt/n8n/.env

# 3. Recreate containers to pick up new env
docker compose -f /opt/n8n/docker-compose.yml up -d --force-recreate
```

### Validate health

```bash
curl -I https://n8n.taurak.co.uk/healthz     # expect HTTP 200
curl -I http://n8n.taurak.co.uk              # expect HTTP 301 redirect to HTTPS
```

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

Both codebases share the `n8n-taurak-state` S3 bucket with separate keys:

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
