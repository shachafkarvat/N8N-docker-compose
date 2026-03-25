# AWS Backup manages both RDS snapshots and EFS backups on a unified schedule.
# RDS automated backups (backup_retention_period = 7) also run independently.

resource "aws_backup_vault" "n8n" {
  name = "n8n-backup-vault"
  tags = local.tags
}

resource "aws_backup_plan" "n8n" {
  name = "n8n-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.n8n.name
    schedule          = "cron(0 3 * * ? *)" # 03:00 UTC every day
    lifecycle {
      delete_after = 7
    }
  }

  rule {
    rule_name         = "weekly"
    target_vault_name = aws_backup_vault.n8n.name
    schedule          = "cron(0 3 ? * SUN *)" # 03:00 UTC every Sunday
    lifecycle {
      delete_after = 28
    }
  }

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.n8n.name
    schedule          = "cron(0 3 1 * ? *)" # 03:00 UTC on the 1st of each month
    lifecycle {
      delete_after = 365
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "n8n-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_selection" "n8n" {
  name         = "n8n-backup-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.n8n.id

  resources = [
    aws_db_instance.n8n.arn,
    aws_efs_file_system.n8n.arn
  ]
}
