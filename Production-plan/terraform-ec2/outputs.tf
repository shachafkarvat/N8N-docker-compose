output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.n8n.id
}

output "n8n_url" {
  description = "n8n application URL"
  value       = "https://${local.fqdn}"
}

output "edge_mode" {
  description = "How HTTPS is terminated at the edge"
  value       = var.enable_alb ? "alb" : "direct-instance"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.enable_alb ? aws_lb.n8n[0].dns_name : null
}

output "direct_public_ip" {
  description = "Elastic IP used for direct-instance mode"
  value       = var.enable_alb ? null : aws_eip.n8n[0].public_ip
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the deployment"
  value       = local.effective_public_subnet_ids
}

output "internet_gateway_id" {
  description = "Internet Gateway used by the deployment"
  value       = local.effective_internet_gateway_id
}

output "ssm_session_command" {
  description = "AWS CLI command to start an interactive shell (no SSH key required)"
  value       = "aws ssm start-session --target ${aws_instance.n8n.id} --region ${var.aws_region}"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for n8n logs"
  value       = aws_cloudwatch_log_group.n8n.name
}

output "backup_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.backups.id
}

output "config_bucket" {
  description = "S3 bucket for runtime config artifacts"
  value       = aws_s3_bucket.config.id
}

output "compose_config_s3_uri" {
  description = "S3 URI for the rendered docker-compose.yml artifact"
  value       = "s3://${aws_s3_object.docker_compose.bucket}/${aws_s3_object.docker_compose.key}"
}

output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.n8n.id
}

output "ecr_repo_url" {
  description = "ECR repository URL for the custom n8n image"
  value       = aws_ecr_repository.n8n.repository_url
}

output "update_n8n_command" {
  description = "Command to update n8n to the latest ECR image"
  value       = "sudo /opt/n8n/update-n8n.sh"
}

output "refresh_config_command" {
  description = "Command to refresh docker-compose.yml from S3 and apply changes in place"
  value       = "sudo /opt/n8n/refresh-config.sh && sudo systemctl restart n8n"
}

output "bootstrap_commands" {
  description = "Commands to run BEFORE first terraform apply"
  value       = <<-EOT
    # 1. Create SSM parameters:
    aws ssm put-parameter --name ${var.db_password_ssm_param} \
      --value "YOUR_STRONG_PASSWORD" --type SecureString --region ${var.aws_region}
    aws ssm put-parameter --name ${var.n8n_encryption_key_ssm_param} \
      --value "YOUR_EXISTING_KEY" --type SecureString --region ${var.aws_region}

    # 2. Build and push custom n8n image (after terraform creates ECR repo):
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin <account>.dkr.ecr.${var.aws_region}.amazonaws.com
    docker build -t n8n-custom:stable /DATA/Work/Projects/N8N/compose/
    docker tag n8n-custom:stable ${aws_ecr_repository.n8n.repository_url}:${var.n8n_image_tag}
    docker push ${aws_ecr_repository.n8n.repository_url}:${var.n8n_image_tag}

    # 3. Fill in terraform.tfvars: vpc_id and either public_subnet_ids or public_subnet_cidrs
  EOT
}
