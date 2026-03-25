locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
  tags = {
    project     = "N8N"
    environment = var.environment
    managed_by  = "terraform"
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
