resource "aws_cloudwatch_log_group" "n8n" {
  name              = "/ec2/n8n"
  retention_in_days = 30
  tags              = local.tags
}
