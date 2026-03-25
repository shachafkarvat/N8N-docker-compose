resource "aws_security_group" "n8n_ec2" {
  name        = "n8n-ec2-sg"
  description = "Security group for n8n EC2 instance — Traefik handles TLS, no SSH needed"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP — Traefik and Let's Encrypt ACME HTTP-01 challenge"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS — n8n access via Traefik"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (Docker image pulls, Let's Encrypt, S3, SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "n8n-ec2-sg" })
}
