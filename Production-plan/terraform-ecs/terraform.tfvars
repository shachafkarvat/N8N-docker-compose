aws_region         = "eu-west-2"
domain_name        = "taurak.co.uk"
subdomain          = "n8n"
route53_zone_id    = "Z773GZMBCOZSA"
environment        = "production"
timezone           = "Europe/London"

# Required — fill in before running terraform apply
vpc_id             = "CHANGE_ME"              # e.g. vpc-0abc1234def567890
public_subnet_ids  = ["CHANGE_ME", "CHANGE_ME"] # e.g. ["subnet-0aaa", "subnet-0bbb"] (PUBLIC subnets in ≥2 AZs)
private_subnet_ids = ["CHANGE_ME", "CHANGE_ME"] # e.g. ["subnet-0ccc", "subnet-0ddd"] (PRIVATE subnets with NAT GW routes)
nat_gateway_id     = "CHANGE_ME"              # e.g. nat-0abc1234def567890

# Database
db_name            = "n8n"
db_username        = "n8n_user"

# ECS task sizing
ecs_task_cpu       = 1024   # 1 vCPU
ecs_task_memory    = 4096   # 4 GB hard limit; container soft limit is 2048 MB

# Backup
backup_bucket_name = "n8n-taurak-backups"
