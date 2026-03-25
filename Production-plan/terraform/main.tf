locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
