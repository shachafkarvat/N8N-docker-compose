variable "aws_region" { default = "eu-west-2" }

variable "vpc_id" {}
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "route53_zone_id" { default = "Z773GZMBCOZSA" }
variable "domain_name" { default = "taurak.co.uk" }
variable "subdomain" { default = "n8n" }

variable "db_name" { default = "n8n" }
variable "db_username" { default = "n8n_user" }
variable "db_password_ssm_param" { default = "/n8n/db_password" }

variable "n8n_encryption_key_ssm_param" { default = "/n8n/encryption_key" }

variable "ecs_task_cpu" { default = 512 }
variable "ecs_task_memory" { default = 1024 }

variable "backup_bucket_name" { default = "n8n-taurak-backups" }
