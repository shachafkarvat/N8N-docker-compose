resource "aws_route53_record" "n8n" {
  zone_id = var.route53_zone_id
  name    = local.fqdn
  type    = "A"
  alias {
    name                   = aws_lb.n8n.dns_name
    zone_id                = aws_lb.n8n.zone_id
    evaluate_target_health = true
  }
}
