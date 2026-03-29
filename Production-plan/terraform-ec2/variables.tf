variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs to reuse. Leave empty to let Terraform create public subnets in the VPC."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets to create when public_subnet_ids is empty. Minimum 2 when ALB is enabled, otherwise 1."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_subnet_ids) > 0 || length(var.public_subnet_cidrs) >= (var.enable_alb ? 2 : 1)
    error_message = "Provide either existing public_subnet_ids or enough public_subnet_cidrs for the selected edge mode. ALB mode needs at least two subnets; direct mode needs at least one."
  }
}

variable "public_subnet_azs" {
  description = "Availability zones for created public subnets. Leave empty to use the first N available AZs in the region."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_subnet_azs) == 0 || length(var.public_subnet_azs) == length(var.public_subnet_cidrs)
    error_message = "When public_subnet_azs is provided, it must have one AZ per public_subnet_cidrs entry."
  }
}

variable "internet_gateway_id" {
  description = "Existing Internet Gateway ID to reuse. Leave null to let Terraform create one for the VPC."
  type        = string
  default     = null
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

variable "use_spot_instance" {
  description = "Launch the n8n EC2 instance as a Spot instance"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum hourly Spot price. Leave null to pay the current Spot market price."
  type        = string
  default     = null
}

variable "spot_valid_until" {
  description = "Optional UTC expiry for the persistent Spot request in RFC3339 format. Leave null for no expiry."
  type        = string
  default     = null
}

variable "enable_alb" {
  description = "When true, deploy an ALB with ACM TLS termination. When false, attach an Elastic IP to the instance and terminate TLS inside Docker using an exported ACM certificate."
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB (holds OS and Docker images only — data is on EFS)"
  default     = 20
}

variable "backup_bucket_name" {
  description = "S3 bucket name for n8n pg_dump backups"
  default     = "n8n-taurak-backups"
}

variable "config_bucket_name" {
  description = "S3 bucket name for versioned runtime config artifacts such as docker-compose.yml"
  default     = "n8n-taurak-config"
}

variable "config_compose_key" {
  description = "S3 object key for the rendered docker-compose.yml artifact"
  default     = "production/docker-compose.yml"
}

variable "db_password_ssm_param" {
  description = "SSM parameter path for the PostgreSQL password (SecureString) — must exist before first apply"
  default     = "/n8n/db_password"
}

variable "n8n_encryption_key_ssm_param" {
  description = "SSM parameter path for the n8n encryption key (SecureString) — must exist before first apply"
  default     = "/n8n/encryption-key"
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
