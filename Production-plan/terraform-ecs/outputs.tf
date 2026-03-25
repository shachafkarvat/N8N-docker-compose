output "n8n_url" {
  description = "n8n application URL"
  value       = "https://${local.fqdn}"
}

output "alb_dns_name" {
  description = "ALB DNS name (use for CNAME if Route53 is not managing the zone)"
  value       = aws_lb.n8n.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address"
  value       = aws_db_instance.n8n.address
}

output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.n8n.id
}

output "efs_access_point_id" {
  description = "EFS access point ID (used in ECS task volume mount)"
  value       = aws_efs_access_point.n8n.id
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS n8n container logs"
  value       = aws_cloudwatch_log_group.n8n.name
}

output "cloudwatch_tail_command" {
  description = "AWS CLI command to tail n8n logs in real time"
  value       = "aws logs tail ${aws_cloudwatch_log_group.n8n.name} --follow --region ${var.aws_region}"
}

output "backup_bucket" {
  description = "S3 bucket name where backups are stored (AWS Backup also writes to vault)"
  value       = aws_s3_bucket.backups.id
}

output "db_password_ssm_param" {
  description = "SSM parameter path for RDS password (update before ECS service starts)"
  value       = aws_ssm_parameter.db_password.name
}

output "encryption_key_ssm_param" {
  description = "SSM parameter path for n8n encryption key (update before ECS service starts)"
  value       = aws_ssm_parameter.encryption_key.name
}

output "ecr_note" {
  description = "Action required to re-enable cheerio support"
  value       = "To re-enable cheerio: build the n8n.Dockerfile, push to ECR, and update the ECS task definition image reference."
}
