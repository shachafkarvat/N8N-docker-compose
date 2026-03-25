data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "n8n_ec2" {
  name               = "n8n-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.tags
}

# SSM Session Manager — no SSH key or port 22 required
resource "aws_iam_role_policy_attachment" "ssm_managed_core" {
  role       = aws_iam_role.n8n_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "n8n_ec2" {
  name        = "n8n-ec2-policy"
  description = "Allows n8n EC2 to read SSM secrets, write backups to S3, and push logs to CloudWatch"

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
        Resource = "*" # AWS-managed key (aws/ssm) — no custom key ARN available
      },
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
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.n8n.arn}:*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "n8n_ec2_attach" {
  role       = aws_iam_role.n8n_ec2.name
  policy_arn = aws_iam_policy.n8n_ec2.arn
}

resource "aws_iam_instance_profile" "n8n_ec2" {
  name = "n8n-ec2-profile"
  role = aws_iam_role.n8n_ec2.name
  tags = local.tags
}
