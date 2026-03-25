output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.n8n.id
}

output "public_ip" {
  description = "Elastic IP address assigned to the instance"
  value       = aws_eip.n8n.public_ip
}

output "n8n_url" {
  description = "n8n application URL"
  value       = "https://${local.fqdn}"
}

output "ssm_session_command" {
  description = "AWS CLI command to start an interactive shell session (no SSH key required)"
  value       = "aws ssm start-session --target ${aws_instance.n8n.id} --region ${var.aws_region}"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for n8n container logs"
  value       = aws_cloudwatch_log_group.n8n.name
}

output "backup_bucket" {
  description = "S3 bucket name where backups are stored"
  value       = aws_s3_bucket.backups.id
}

output "db_password_ssm_param" {
  description = "SSM parameter path for PostgreSQL password (update this before first boot)"
  value       = aws_ssm_parameter.db_password.name
}

output "encryption_key_ssm_param" {
  description = "SSM parameter path for n8n encryption key (update this before first boot)"
  value       = aws_ssm_parameter.encryption_key.name
}
