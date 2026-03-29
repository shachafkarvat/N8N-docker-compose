resource "aws_route53_record" "n8n_alb" {
  count   = var.enable_alb ? 1 : 0
  zone_id = var.route53_zone_id
  name    = local.fqdn
  type    = "A"
  alias {
    name                   = aws_lb.n8n[0].dns_name
    zone_id                = aws_lb.n8n[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "n8n_direct" {
  count   = var.enable_alb ? 0 : 1
  zone_id = var.route53_zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.n8n[0].public_ip]
}
