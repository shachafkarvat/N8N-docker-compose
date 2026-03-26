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
  subnet_id              = var.public_subnet_ids[0]
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
    aws_region           = var.aws_region
    fqdn                 = local.fqdn
    timezone             = var.timezone
    backup_bucket        = var.backup_bucket_name
    db_password_param    = var.db_password_ssm_param
    encryption_key_param = var.n8n_encryption_key_ssm_param
    cloudwatch_log_group = aws_cloudwatch_log_group.n8n.name
    ecr_repo_url         = aws_ecr_repository.n8n.repository_url
    ecr_image_tag        = var.n8n_image_tag
    efs_id               = aws_efs_file_system.n8n.id
    efs_ap_n8n_data      = aws_efs_access_point.n8n_data.id
    efs_ap_local_files   = aws_efs_access_point.n8n_local_files.id
    efs_ap_postgres      = aws_efs_access_point.postgres_data.id
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2  # 2 hops needed for Docker containers to reach IMDS
  }

  tags = merge(local.tags, { Name = "n8n-instance" })

  depends_on = [
    aws_efs_mount_target.n8n
  ]
}
