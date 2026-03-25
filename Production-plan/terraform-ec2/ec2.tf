# Latest Amazon Linux 2023 ARM64 AMI (for Graviton t4g instances)
data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "n8n" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.n8n_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.n8n_ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.tags, { Name = "n8n-root-volume" })
  }

  user_data = templatefile("${path.module}/templates/userdata.sh.tpl", {
    aws_region               = var.aws_region
    fqdn                     = local.fqdn
    domain_name              = var.domain_name
    subdomain                = var.subdomain
    ssl_email                = var.ssl_email
    timezone                 = var.timezone
    backup_bucket            = var.backup_bucket_name
    db_password_param        = var.db_password_ssm_param
    encryption_key_param     = var.n8n_encryption_key_ssm_param
    cloudwatch_log_group     = aws_cloudwatch_log_group.n8n.name
  })

  # Require IMDSv2 for improved instance metadata security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, { Name = "n8n-instance" })

  # Ensure SSM parameters exist before the instance boots and reads them
  depends_on = [
    aws_ssm_parameter.db_password,
    aws_ssm_parameter.encryption_key
  ]
}

resource "aws_eip" "n8n" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "n8n-eip" })
}

resource "aws_eip_association" "n8n" {
  instance_id   = aws_instance.n8n.id
  allocation_id = aws_eip.n8n.id
}
