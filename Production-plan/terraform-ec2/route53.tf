resource "aws_route53_record" "n8n" {
  zone_id = var.route53_zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.n8n.public_ip]
}
