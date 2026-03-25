resource "aws_efs_file_system" "n8n" {
  creation_token = "n8n-efs"
  encrypted      = true

  tags = merge(local.tags, { Name = "n8n-efs" })
}

# One mount target per private subnet
resource "aws_efs_mount_target" "n8n" {
  for_each        = toset(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.n8n.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}

# Access point scoped to UID/GID 1000 (the node user n8n runs as)
resource "aws_efs_access_point" "n8n" {
  file_system_id = aws_efs_file_system.n8n.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/n8n"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.tags, { Name = "n8n-access-point" })
}

# File system policy — deny all non-TLS connections
resource "aws_efs_file_system_policy" "n8n" {
  file_system_id = aws_efs_file_system.n8n.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "elasticfilesystem:*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
