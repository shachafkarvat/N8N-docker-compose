data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── Execution Role ──────────────────────────────────────────────────────────
# Used by the ECS control plane to pull secrets and send logs during task startup.
resource "aws_iam_role" "ecs_execution" {
  name               = "n8n-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# SSM secret injection happens via the execution role, not the task role.
resource "aws_iam_policy" "ecs_exec_ssm" {
  name        = "n8n-ecs-exec-ssm"
  description = "Allow ECS execution role to read SSM SecureStrings for container secret injection"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSSMSecrets"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.db_password.arn,
          aws_ssm_parameter.encryption_key.arn
        ]
      },
      {
        Sid      = "DecryptSSMSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*" # AWS-managed key (aws/ssm) — no customer-managed key
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_exec_ssm_attach" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_exec_ssm.arn
}

# ── Task Role ───────────────────────────────────────────────────────────────
# Used by the n8n process running inside the container.
resource "aws_iam_role" "ecs_task" {
  name               = "n8n-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "ecs_task" {
  name        = "n8n-ecs-task-policy"
  description = "Allow n8n container to mount EFS and write backups to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Backups"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      },
      {
        Sid    = "EFSAccess"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.n8n.arn
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_attach" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task.arn
}
