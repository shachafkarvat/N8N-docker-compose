data "aws_ssm_parameter" "db_password" {
  name            = var.db_password_ssm_param
  with_decryption = true
}
