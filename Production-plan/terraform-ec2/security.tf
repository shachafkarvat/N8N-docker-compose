# ── ALB Security Group ─────────────────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name        = "n8n-alb-sg"
  description = "ALB — accepts HTTPS from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP — redirected to HTTPS by ALB listener"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-alb-sg" })
}

# ── EC2 Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "n8n_ec2" {
  name        = "n8n-ec2-sg"
  description = "n8n EC2 instance — inbound only from ALB, plus NFS to EFS"
  vpc_id      = var.vpc_id

  # n8n port from ALB only (no public 80/443 on the instance)
  ingress {
    description     = "n8n from ALB"
    from_port       = 5678
    to_port         = 5678
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "All outbound (ECR pull, SSM, S3, NFS, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-ec2-sg" })
}

# ── EFS Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "efs_sg" {
  name        = "n8n-efs-sg"
  description = "EFS mount targets — NFS from EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from EC2"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.n8n_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-efs-sg" })
}
