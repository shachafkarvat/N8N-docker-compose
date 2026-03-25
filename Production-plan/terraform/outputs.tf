output "alb_dns_name" {
  value = aws_lb.n8n.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.n8n.address
}
