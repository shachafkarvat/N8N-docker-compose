# terraform-ec2 — n8n on AWS EC2

Terraform module that deploys a production n8n instance on a single EC2 instance (Graviton ARM64) with two edge modes:

- direct instance mode by default: Elastic IP + Route53 A record + exported ACM certificate terminated inside Docker
- optional ALB mode: ALB + Route53 ALIAS + ACM TLS termination on the load balancer

Persistent data lives on EFS, the custom image comes from ECR, and S3 stores backups plus runtime config artifacts.

## Architecture

```
Direct mode:
Internet → Route53 A → Elastic IP → nginx in Docker (ACM TLS) → n8n + Postgres

ALB mode:
Internet → Route53 ALIAS → ALB (ACM TLS) → EC2:5678 (n8n + Postgres)

Shared persistence:
EC2 ↕ EFS (3 access points: n8n-data / local-files / postgres-data)
```

| Component | Service | Notes |
|---|---|---|
| Compute | EC2 `t4g.small` Spot by default | Persistent Spot request with stop behavior |
| Edge | Direct instance by default, optional ALB | Controlled by `enable_alb` |
| TLS | ACM certificate | Direct mode exports ACM to the instance; ALB mode attaches ACM to the ALB |
| DNS | Route53 A → EIP or ALIAS → ALB | Automatic based on `enable_alb` |
| Persistent data | EFS (3 access points) | Survives instance replacement |
| Container image | ECR (`taurak/n8n:stable`) | Custom n8n + cheerio |
| Runtime config | S3 (`n8n-taurak-config`) | Versioned `docker-compose.yml` artifact synced to EC2 |
| Secrets | SSM Parameter Store (SecureString) | Never written to disk in plaintext |
| Backups | S3 (`n8n-taurak-backups`) | Daily at 02:00 UTC, tiered retention |
| Logs | CloudWatch Logs | `/ec2/n8n` log group |
| Shell access | SSM Session Manager | No SSH key or port 22 needed |
| State | S3 + DynamoDB lock | `n8n-taurak-tfstate` / `n8n-taurak-state-lock` |

### Security groups

- **Direct mode**: EC2 SG exposes 80 and 443 only; n8n itself stays private behind nginx in Docker
- **ALB mode**: ALB SG exposes 80 and 443; EC2 SG exposes 5678 only from the ALB SG
- **All modes**: EFS SG exposes NFS 2049 only from the EC2 SG

### Certificate behavior

- `enable_alb = false`: Terraform requests an exportable ACM public certificate and the instance exports it at boot using `acm:ExportCertificate`. No Let's Encrypt is used.
- `enable_alb = true`: Terraform requests a standard ACM public certificate and attaches it to the ALB.

Direct mode uses an exportable ACM public certificate, which carries an ACM charge. ALB mode keeps the previous no-additional-cost ACM pattern.

---

## Prerequisites

- Terraform ≥ 1.6, AWS provider ~> 6.0
- AWS CLI configured with sufficient permissions
- An existing VPC. If it does not already have public subnets, this module can create them.
- A Route53 hosted zone for your domain

---

## First-time setup

### 1. Bootstrap the remote state backend

Run once before any `terraform` commands:

```bash
../scripts/bootstrap-state.sh
```

This creates the S3 state bucket (`n8n-taurak-tfstate`) with versioning enabled, and the DynamoDB lock table (`n8n-taurak-state-lock`).

### 2. Fill in terraform.tfvars

Edit `terraform.tfvars` and set your VPC details. You can either:

- reuse existing public subnets with `public_subnet_ids`, or
- let Terraform create public subnets with `public_subnet_cidrs`

Example using created public subnets:

```hcl
vpc_id            = "vpc-0abc1234def567890"
public_subnet_ids = []
public_subnet_cidrs = ["10.20.10.0/24", "10.20.20.0/24"]
public_subnet_azs   = ["eu-west-2a", "eu-west-2b"]
enable_alb          = false
use_spot_instance   = true
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
  --name "/n8n/encryption-key" \
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
5. Downloads the versioned `docker-compose.yml` artifact from S3 to `/opt/n8n/`
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
aws logs tail /ec2/n8n --follow --region eu-west-2
```

### Refresh runtime config

After updating the Compose template and applying Terraform, refresh the running instance in place:

```bash
sudo /opt/n8n/refresh-config.sh
sudo systemctl restart n8n
```

This pulls the latest rendered `docker-compose.yml` from S3 without recreating the EC2 instance.

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
| `alb.tf` | Optional ALB, target group, HTTPS listener, HTTP→HTTPS redirect |
| `ec2.tf` | EC2 instance + instance profile + userdata rendering |
| `ecr.tf` | ECR repository + lifecycle policy (keep 5 images) |
| `efs.tf` | EFS file system + 3 access points + TLS mount policy |
| `iam.tf` | IAM role + policy (SSM, ECR, EFS, S3, CloudWatch) |
| `security.tf` | Three security groups: ALB, EC2, EFS |
| `ssm.tf` | SSM parameter data sources (read-only) |
| `route53.tf` | Route53 ALIAS → ALB or A record → EIP |
| `s3.tf` | S3 backup bucket + runtime config bucket + Compose artifact |
| `cloudwatch.tf` | CloudWatch log group |
| `outputs.tf` | Instance ID, URL, ALB DNS, SSM session command, etc. |
| `templates/docker-compose.yml.tpl` | Rendered Compose artifact stored in S3, with conditional nginx edge service |
| `templates/userdata.sh.tpl` | EC2 bootstrap script (Terraform templatefile) |

---

## Outputs

| Output | Description |
|---|---|
| `n8n_url` | Application URL (`https://n8n.taurak.co.uk`) |
| `edge_mode` | `alb` or `direct-instance` |
| `alb_dns_name` | Raw ALB DNS name when `enable_alb = true` |
| `direct_public_ip` | Elastic IP when `enable_alb = false` |
| `public_subnet_ids` | Public subnets used by ALB, EC2, and EFS mount targets |
| `internet_gateway_id` | Internet Gateway used by the public route table |
| `instance_id` | EC2 instance ID |
| `ssm_session_command` | Full AWS CLI command for shell access |
| `ecr_repo_url` | ECR URL for building/pushing the custom image |
| `efs_id` | EFS file system ID |
| `cloudwatch_log_group` | CloudWatch log group name |
| `backup_bucket` | S3 backup bucket name |
| `config_bucket` | S3 runtime config bucket name |
| `compose_config_s3_uri` | S3 URI of the rendered `docker-compose.yml` |
| `update_n8n_command` | Command to run on instance to pull a new image |
| `refresh_config_command` | Command to sync and apply Compose changes in place |
| `bootstrap_commands` | Reminder of pre-apply steps |
