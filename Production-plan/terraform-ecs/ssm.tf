# SSM SecureString parameters for sensitive values.
# Terraform creates these with placeholder values on first apply.
# IMPORTANT: Update the actual values via AWS console or CLI BEFORE running
# terraform apply a second time (or before the ECS service starts), because
# the ECS task definition references these ARNs for secret injection.
#
#   aws ssm put-parameter --name /n8n/db_password \
#     --value "your-strong-password" --type SecureString --overwrite --region eu-west-2
#
#   aws ssm put-parameter --name /n8n/encryption_key \
#     --value "$(openssl rand -hex 32)" --type SecureString --overwrite --region eu-west-2

resource "aws_ssm_parameter" "db_password" {
  name        = var.db_password_ssm_param
  description = "RDS PostgreSQL master password for n8n"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_ECS_STARTS"

  lifecycle {
    ignore_changes = [value] # Terraform creates the param; humans update the value
  }

  tags = local.tags
}

resource "aws_ssm_parameter" "encryption_key" {
  name        = var.n8n_encryption_key_ssm_param
  description = "n8n encryption key — MUST match the value used when PostgreSQL was first populated"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_ECS_STARTS"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.tags
}
