# SSM SecureString parameters for sensitive values.
# Terraform creates these with placeholder values on first apply.
# IMPORTANT: Update the actual values via AWS console or CLI BEFORE the
# EC2 instance boots for the first time, as userdata fetches them at startup.
#
#   aws ssm put-parameter --name /n8n/db_password \
#     --value "your-strong-password" --type SecureString --overwrite --region eu-west-2
#
#   aws ssm put-parameter --name /n8n/encryption_key \
#     --value "$(openssl rand -hex 32)" --type SecureString --overwrite --region eu-west-2

resource "aws_ssm_parameter" "db_password" {
  name        = var.db_password_ssm_param
  description = "PostgreSQL password for the n8n database"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_FIRST_BOOT"

  lifecycle {
    ignore_changes = [value] # Terraform creates the param; humans update the value
  }

  tags = local.tags
}

resource "aws_ssm_parameter" "encryption_key" {
  name        = var.n8n_encryption_key_ssm_param
  description = "n8n encryption key — MUST match the value used when the database was first created"
  type        = "SecureString"
  value       = "CHANGE_ME_BEFORE_FIRST_BOOT"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.tags
}
