variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs — minimum 2 for ALB. EC2 instance launched in the first one."
  type        = list(string)
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

variable "instance_type" {
  description = "EC2 instance type — t4g.* uses Graviton ARM64 for best price/performance"
  default     = "t4g.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB (holds OS and Docker images only — data is on EFS)"
  default     = 20
}

variable "backup_bucket_name" {
  description = "S3 bucket name for n8n pg_dump backups"
  default     = "n8n-taurak-backups"
}

variable "db_password_ssm_param" {
  description = "SSM parameter path for the PostgreSQL password (SecureString) — must exist before first apply"
  default     = "/n8n/db_password"
}

variable "n8n_encryption_key_ssm_param" {
  description = "SSM parameter path for the n8n encryption key (SecureString) — must exist before first apply"
  default     = "/n8n/encryption_key"
}

variable "timezone" {
  description = "Timezone for n8n scheduler and logs"
  default     = "Europe/London"
}

variable "n8n_ecr_repo_name" {
  description = "ECR repository name for the custom n8n image (with cheerio)"
  default     = "taurak/n8n"
}

variable "n8n_image_tag" {
  description = "Docker image tag for the custom n8n image in ECR"
  default     = "stable"
}
