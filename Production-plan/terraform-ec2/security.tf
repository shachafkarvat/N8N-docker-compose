# ── ALB Security Group ─────────────────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  count       = var.enable_alb ? 1 : 0
  name        = "n8n-alb-sg"
  description = "ALB - accepts HTTPS from the internet"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count             = var.enable_alb ? 1 : 0
  security_group_id = aws_security_group.alb_sg[0].id
  description       = "HTTP - redirected to HTTPS by ALB listener"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.enable_alb ? 1 : 0
  security_group_id = aws_security_group.alb_sg[0].id
  description       = "HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ── EC2 Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "n8n_ec2" {
  name        = "n8n-ec2-sg"
  description = "n8n EC2 instance - inbound from ALB in ALB mode or public 80/443 in direct mode"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (ECR pull, SSM, S3, NFS, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-ec2-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "n8n_from_alb" {
  count                        = var.enable_alb ? 1 : 0
  security_group_id            = aws_security_group.n8n_ec2.id
  description                  = "n8n from ALB"
  referenced_security_group_id = aws_security_group.alb_sg[0].id
  from_port                    = 5678
  to_port                      = 5678
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "n8n_direct_http" {
  count             = var.enable_alb ? 0 : 1
  security_group_id = aws_security_group.n8n_ec2.id
  description       = "HTTP redirect to HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "n8n_direct_https" {
  count             = var.enable_alb ? 0 : 1
  security_group_id = aws_security_group.n8n_ec2.id
  description       = "HTTPS direct access"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ── EFS Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "efs_sg" {
  name        = "n8n-efs-sg"
  description = "EFS mount targets - NFS from EC2 only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-efs-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_ec2" {
  security_group_id            = aws_security_group.efs_sg.id
  description                  = "NFS from EC2"
  referenced_security_group_id = aws_security_group.n8n_ec2.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}
