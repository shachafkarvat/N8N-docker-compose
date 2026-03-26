output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.n8n.id
}

output "n8n_url" {
  description = "n8n application URL"
  value       = "https://${local.fqdn}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.n8n.dns_name
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

    # 3. Fill in terraform.tfvars: vpc_id, public_subnet_ids
  EOT
}
