resource "aws_security_group" "alb_sg" {
  name        = "n8n-alb-sg"
  description = "ALB — accepts HTTP and HTTPS from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP — redirected to HTTPS by ALB listener"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS — n8n access"
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

resource "aws_security_group" "ecs_sg" {
  name        = "n8n-ecs-sg"
  description = "ECS Fargate tasks — inbound only from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "n8n port from ALB only"
    from_port       = 5678
    to_port         = 5678
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Allow all outbound (RDS, EFS, SSM, CloudWatch, NAT for image pull)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-ecs-sg" })
}

resource "aws_security_group" "rds_sg" {
  name        = "n8n-rds-sg"
  description = "RDS PostgreSQL — inbound only from ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # No egress rule needed for RDS

  tags = merge(local.tags, { Name = "n8n-rds-sg" })
}

resource "aws_security_group" "efs_sg" {
  name        = "n8n-efs-sg"
  description = "EFS mount targets — inbound NFS only from ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from ECS only"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    description = "Allow NFS response traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-efs-sg" })
}
