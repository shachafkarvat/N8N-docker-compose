# SSM SecureString parameters for sensitive values.
#
# MUST be created via CLI BEFORE first terraform apply:
#
#   aws ssm put-parameter --name /n8n/db_password \
#     --value "your-strong-password" --type SecureString --region eu-west-2
#
#   aws ssm put-parameter --name /n8n/encryption_key \
#     --value "your-existing-key" --type SecureString --region eu-west-2
#
# Terraform reads them as data sources — does NOT create or manage values.

data "aws_ssm_parameter" "db_password" {
  name            = var.db_password_ssm_param
  with_decryption = true
}

data "aws_ssm_parameter" "encryption_key" {
  name            = var.n8n_encryption_key_ssm_param
  with_decryption = true
}
