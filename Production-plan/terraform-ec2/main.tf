locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
  tags = {
    project     = "N8N"
    environment = var.environment
    managed_by  = "terraform"
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

locals {
  created_public_subnet_azs = length(var.public_subnet_azs) > 0 ? var.public_subnet_azs : slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  created_public_subnets = {
    for idx, cidr in var.public_subnet_cidrs : format("%02d", idx) => {
      cidr = cidr
      az   = local.created_public_subnet_azs[idx]
    }
  }

  effective_public_subnet_ids   = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : [for subnet in aws_subnet.public : subnet.id]
  effective_public_subnet_map   = length(var.public_subnet_ids) > 0 ? { for idx, id in var.public_subnet_ids : format("%02d", idx) => id } : { for k, subnet in aws_subnet.public : k => subnet.id }
  effective_internet_gateway_id = var.internet_gateway_id != null ? var.internet_gateway_id : aws_internet_gateway.public[0].id
  n8n_proxy_hops                = 1
}
