aws_region         = "eu-west-2"
domain_name        = "taurak.co.uk"
subdomain          = "n8n"
route53_zone_id    = "Z773GZMBCOZSA"
environment        = "production"
timezone           = "Europe/London"

# Required — fill in before running terraform apply
vpc_id             = "CHANGE_ME"                       # e.g. vpc-0abc1234def567890
public_subnet_ids  = ["CHANGE_ME", "CHANGE_ME"]        # e.g. ["subnet-0aaa", "subnet-0bbb"] (PUBLIC, ≥2 AZs for ALB)

# Instance config
instance_type      = "t4g.small"    # 2 vCPU / 2 GB — sufficient for n8n with Postgres container
root_volume_size   = 20             # GB — OS + Docker images only (data on EFS)

# Custom n8n image — MUST be built and pushed to ECR before apply
n8n_ecr_repo_name  = "taurak/n8n"
n8n_image_tag      = "stable"

# Backup
backup_bucket_name = "n8n-taurak-backups"
