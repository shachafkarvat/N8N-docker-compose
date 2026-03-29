# EFS for all persistent n8n data — survives EC2 instance termination.
# Three access points isolate the data types:
#   1. n8n-data: /home/node/.n8n (credentials, encryption key, config)
#   2. n8n-local-files: /files (workflow file I/O)
#   3. postgres-data: /var/lib/postgresql/data (database files)

resource "aws_efs_file_system" "n8n" {
  creation_token = "n8n-efs"
  encrypted      = true

  # Infrequent Access tier saves ~92% on storage for files not accessed in 30 days
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.tags, { Name = "n8n-efs" })
}

# Mount targets in each subnet the EC2 instance might live in
resource "aws_efs_mount_target" "n8n" {
  for_each        = local.effective_public_subnet_map
  file_system_id  = aws_efs_file_system.n8n.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}

# ── Access Point 1: n8n application data ──────────────────────────────────
resource "aws_efs_access_point" "n8n_data" {
  file_system_id = aws_efs_file_system.n8n.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/n8n-data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.tags, { Name = "n8n-data-ap" })
}

# ── Access Point 2: local-files (/files) ──────────────────────────────────
resource "aws_efs_access_point" "n8n_local_files" {
  file_system_id = aws_efs_file_system.n8n.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/n8n-local-files"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.tags, { Name = "n8n-local-files-ap" })
}

# ── Access Point 3: PostgreSQL data ───────────────────────────────────────
resource "aws_efs_access_point" "postgres_data" {
  file_system_id = aws_efs_file_system.n8n.id

  posix_user {
    uid = 999 # postgres user UID in official postgres:16-alpine image
    gid = 999
  }

  root_directory {
    path = "/postgres-data"
    creation_info {
      owner_uid   = 999
      owner_gid   = 999
      permissions = "700"
    }
  }

  tags = merge(local.tags, { Name = "n8n-postgres-data-ap" })
}

# Enforce TLS and allow access from the EC2 role
resource "aws_efs_file_system_policy" "n8n" {
  file_system_id = aws_efs_file_system.n8n.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTLSAccess"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      },
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
