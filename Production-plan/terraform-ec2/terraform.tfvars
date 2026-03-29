aws_region        = "eu-west-2"
domain_name       = "taurak.co.uk"
subdomain         = "n8n"
route53_zone_id   = "Z773GZMBCOZSA"
environment       = "production"
timezone          = "Europe/London"
enable_alb        = false
use_spot_instance = true
spot_max_price    = "0.0120"

# Required — fill in before running terraform apply
vpc_id = "vpc-03f61bb823ebb21c8"

# This VPC currently has no subnets or Internet Gateway attached.
# Terraform will create two public subnets and a public route via a new IGW.
public_subnet_ids   = []
public_subnet_cidrs = ["10.20.10.0/24", "10.20.20.0/24"]
public_subnet_azs   = ["eu-west-2a", "eu-west-2b"]

# Instance config
instance_type    = "t4g.small" # 2 vCPU / 2 GB — sufficient for n8n with Postgres container
root_volume_size = 30          # GB — OS + Docker images only (data on EFS)

# Custom n8n image — MUST be built and pushed to ECR before apply
n8n_ecr_repo_name = "taurak/n8n"
n8n_image_tag     = "stable"

# Backup
backup_bucket_name = "n8n-taurak-backups"
