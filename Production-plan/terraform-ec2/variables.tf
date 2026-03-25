variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
}

variable "public_subnet_id" {
  description = "ID of a public subnet for the EC2 instance (must have an internet gateway route and auto-assign public IP enabled)"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain"
  default     = "Z773GZMBCOZSA"
}

variable "domain_name" {
  description = "Root domain name"
  default     = "taurak.co.uk"
}

variable "subdomain" {
  description = "Subdomain for n8n"
  default     = "n8n"
}

variable "environment" {
  description = "Environment name used in resource tags"
  default     = "production"
}

variable "ssl_email" {
  description = "Email address for Let's Encrypt certificate notifications (used by Traefik)"
}

variable "instance_type" {
  description = "EC2 instance type — t4g.* uses Graviton ARM64 for best price/performance"
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB (holds OS, Docker images, volumes, and backups)"
  default     = 30
}

variable "backup_bucket_name" {
  description = "S3 bucket name for n8n backups"
  default     = "n8n-taurak-backups"
}

variable "db_password_ssm_param" {
  description = "SSM parameter path for the PostgreSQL password (SecureString)"
  default     = "/n8n/db_password"
}

variable "n8n_encryption_key_ssm_param" {
  description = "SSM parameter path for the n8n encryption key (SecureString)"
  default     = "/n8n/encryption_key"
}

variable "timezone" {
  description = "Timezone for n8n scheduler and logs"
  default     = "Europe/London"
}
