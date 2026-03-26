# ALB replaces Traefik for TLS termination. Benefits:
# - No port 80/443 exposed on the EC2 instance
# - ACM certificate (free, auto-renewing) replaces Let's Encrypt
# - Health checks with automatic target deregistration
# - Webhook-friendly idle timeout
#
# Cost: ~£16/month (fixed) + ~£0.60/LCU-hour (minimal for n8n traffic)

resource "aws_lb" "n8n" {
  name               = "n8n-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 3600 # n8n webhooks hold connections open

  tags = local.tags
}

resource "aws_lb_target_group" "n8n" {
  name        = "n8n-tg"
  port        = 5678
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    port                = "5678"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "n8n" {
  target_group_arn = aws_lb_target_group.n8n.arn
  target_id        = aws_instance.n8n.id
  port             = 5678
}

# Redirect HTTP → HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.n8n.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.n8n.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.n8n.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.n8n.arn
  }
}
