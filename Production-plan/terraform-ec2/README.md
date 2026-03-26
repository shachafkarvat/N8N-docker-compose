# terraform-ec2 — n8n on AWS EC2

Terraform module that deploys a production n8n instance on a single EC2 instance (Graviton ARM64) with ALB for TLS termination, EFS for persistent data, ECR for the custom image, and S3 for backups.

## Architecture

```
Internet → ALB (ACM TLS) → EC2:5678 (n8n + Postgres in Docker)
                                  ↕
                              EFS (3 access points)
                         n8n-data / local-files / postgres-data
```

| Component | Service | Notes |
|---|---|---|
| Compute | EC2 `t4g.small` (Graviton ARM64) | 2 vCPU / 2 GB RAM |
| TLS | ALB + ACM certificate | Auto-renewing, no Let's Encrypt on instance |
| DNS | Route53 ALIAS → ALB | TTL managed by ALB |
| Persistent data | EFS (3 access points) | Survives instance replacement |
| Container image | ECR (`taurak/n8n:stable`) | Custom n8n + cheerio |
| Secrets | SSM Parameter Store (SecureString) | Never written to disk in plaintext |
| Backups | S3 (`n8n-taurak-backups`) | Daily at 02:00 UTC, tiered retention |
| Logs | CloudWatch Logs | `/n8n/production` log group |
| Shell access | SSM Session Manager | No SSH key or port 22 needed |
| State | S3 + DynamoDB lock | `n8n-taurak-state` / `n8n-taurak-state-lock` |

### Security groups

- **ALB SG**: 80 + 443 from `0.0.0.0/0`
- **EC2 SG**: port 5678 from ALB SG only (not publicly reachable)
- **EFS SG**: NFS 2049 from EC2 SG only

---

## Prerequisites

- Terraform ≥ 1.6, AWS provider ~> 5.0
- AWS CLI configured with sufficient permissions
- An existing VPC with ≥ 2 public subnets in different AZs (required for ALB)
- A Route53 hosted zone for your domain

---

## First-time setup

### 1. Bootstrap the remote state backend

Run once before any `terraform` commands:

```bash
../scripts/bootstrap-state.sh
```

This creates the S3 state bucket (`n8n-taurak-state`) with versioning enabled, and the DynamoDB lock table (`n8n-taurak-state-lock`).

### 2. Fill in terraform.tfvars

Edit `terraform.tfvars` and replace the `CHANGE_ME` values:

```hcl
vpc_id            = "vpc-0abc1234def567890"
public_subnet_ids = ["subnet-0aaa...", "subnet-0bbb..."]  # ≥2 AZs, public
```

### 3. Create the ECR repository first

The custom n8n image must exist in ECR before the EC2 instance boots. Create the repo first:

```bash
terraform init
terraform apply -target=aws_ecr_repository.n8n
```

### 4. Build and push the custom n8n image

From the root of this repo (where `n8n.Dockerfile` lives):

```bash
# Get your account ID and ECR URL from terraform output
ECR_URL=$(terraform output -raw ecr_repo_url)
AWS_REGION="eu-west-2"

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $(echo $ECR_URL | cut -d/ -f1)

docker build -t n8n-custom:stable -f /DATA/Work/Projects/N8N/compose/n8n.Dockerfile \
  /DATA/Work/Projects/N8N/compose/
docker tag n8n-custom:stable $ECR_URL:stable
docker push $ECR_URL:stable
```

### 5. Create SSM parameters

These **must exist** before `terraform apply` runs, as they are read-only `data` sources:

```bash
aws ssm put-parameter \
  --name "/n8n/db_password" \
  --value "YOUR_STRONG_PASSWORD" \
  --type SecureString \
  --region eu-west-2

aws ssm put-parameter \
  --name "/n8n/encryption_key" \
  --value "$(openssl rand -hex 32)" \
  --type SecureString \
  --region eu-west-2
```

> **Important:** Save the `encryption_key` value. If you lose it, all n8n credentials stored in the database become unreadable and must be re-entered.

### 6. Apply

```bash
terraform apply
```

After apply, the instance boots and runs `userdata.sh.tpl`, which:
1. Installs Docker + Docker Compose v2
2. Fetches secrets from SSM into memory (never written to disk)
3. Mounts EFS at `/mnt/efs/{n8n-data,local-files,postgres-data}`
4. Authenticates to ECR and pulls the custom n8n image
5. Writes a `docker-compose.yml` to `/opt/n8n/`
6. Registers and starts a `n8n` systemd service
7. Starts the CloudWatch agent
8. Installs a daily backup cron (02:00 UTC)

Allow 3–5 minutes for the instance to fully start after `apply` completes.

---

## Day-to-day operations

### Access the instance shell

No SSH key needed — use SSM Session Manager:

```bash
$(terraform output -raw ssm_session_command)
# or manually:
aws ssm start-session --target <instance-id> --region eu-west-2
```

### View logs

```bash
# From inside the instance:
docker compose -f /opt/n8n/docker-compose.yml logs -f n8n

# From your workstation (CloudWatch):
aws logs tail /n8n/production --follow --region eu-west-2
```

### Update n8n to a new image

Build and push a new image to ECR (step 4 above), then on the instance:

```bash
sudo /opt/n8n/update-n8n.sh
```

### Manual backup

```bash
sudo /opt/n8n/backup.sh
```

Backups go to S3 under `s3://n8n-taurak-backups/` with tiered prefixes:
- `daily/` — retained 7 days
- `weekly/` — Sunday backups, retained 28 days
- `monthly/` — 1st of month, retained 365 days

---

## File reference

| File | Purpose |
|---|---|
| `main.tf` | Locals, data sources (VPC, caller identity) |
| `versions.tf` | Terraform + AWS provider version constraints |
| `backend.tf` | S3 remote state + DynamoDB lock |
| `variables.tf` | All input variables with defaults |
| `terraform.tfvars` | Environment-specific values (fill in before apply) |
| `acm.tf` | ACM certificate + Route53 DNS validation |
| `alb.tf` | ALB, target group, HTTPS listener, HTTP→HTTPS redirect |
| `ec2.tf` | EC2 instance + instance profile + userdata rendering |
| `ecr.tf` | ECR repository + lifecycle policy (keep 5 images) |
| `efs.tf` | EFS file system + 3 access points + TLS mount policy |
| `iam.tf` | IAM role + policy (SSM, ECR, EFS, S3, CloudWatch) |
| `security.tf` | Three security groups: ALB, EC2, EFS |
| `ssm.tf` | SSM parameter data sources (read-only) |
| `route53.tf` | Route53 ALIAS record → ALB |
| `s3.tf` | S3 backup bucket |
| `cloudwatch.tf` | CloudWatch log group |
| `outputs.tf` | Instance ID, URL, ALB DNS, SSM session command, etc. |
| `templates/userdata.sh.tpl` | EC2 bootstrap script (Terraform templatefile) |

---

## Outputs

| Output | Description |
|---|---|
| `n8n_url` | Application URL (`https://n8n.taurak.co.uk`) |
| `alb_dns_name` | Raw ALB DNS name (used for Route53 ALIAS) |
| `instance_id` | EC2 instance ID |
| `ssm_session_command` | Full AWS CLI command for shell access |
| `ecr_repo_url` | ECR URL for building/pushing the custom image |
| `efs_id` | EFS file system ID |
| `cloudwatch_log_group` | CloudWatch log group name |
| `backup_bucket` | S3 backup bucket name |
| `update_n8n_command` | Command to run on instance to pull a new image |
| `bootstrap_commands` | Reminder of pre-apply steps |
