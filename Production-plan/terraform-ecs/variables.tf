variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB (minimum 2 for ALB availability zones)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks and RDS (must already have NAT GW routes)"
  type        = list(string)
}

variable "nat_gateway_id" {
  description = "ID of the existing NAT Gateway that the private subnets route through"
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

variable "timezone" {
  description = "Timezone for n8n scheduler and logs"
  default     = "Europe/London"
}

variable "db_name" {
  description = "PostgreSQL database name"
  default     = "n8n"
}

variable "db_username" {
  description = "PostgreSQL master username"
  default     = "n8n_user"
}

variable "db_password_ssm_param" {
  description = "SSM parameter path for the RDS master password (SecureString)"
  default     = "/n8n/db_password"
}

variable "n8n_encryption_key_ssm_param" {
  description = "SSM parameter path for the n8n encryption key (SecureString)"
  default     = "/n8n/encryption_key"
}

variable "ecs_task_cpu" {
  description = "ECS task CPU units (1024 = 1 vCPU)"
  default     = 1024
}

variable "ecs_task_memory" {
  description = "ECS task memory in MB (hard limit — container soft limit is 2048)"
  default     = 4096
}

variable "backup_bucket_name" {
  description = "S3 bucket name for n8n backups"
  default     = "n8n-taurak-backups"
}
