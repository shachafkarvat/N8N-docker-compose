aws_region         = "eu-west-2"
domain_name        = "taurak.co.uk"
subdomain          = "n8n"
route53_zone_id    = "Z773GZMBCOZSA"
environment        = "production"

# Required — fill in before running terraform apply
ssl_email          = "CHANGE_ME"        # e.g. admin@taurak.co.uk
vpc_id             = "CHANGE_ME"        # e.g. vpc-0abc1234def567890
public_subnet_id   = "CHANGE_ME"        # e.g. subnet-0abc1234 (must be a PUBLIC subnet)

# Instance config
instance_type      = "t4g.medium"       # 2 vCPU / 4 GB RAM, Graviton ARM64
root_volume_size   = 30                 # GB — stores OS, Docker images, n8n data volumes

# Backup
backup_bucket_name = "n8n-taurak-backups"

# Timezone
timezone           = "Europe/London"
