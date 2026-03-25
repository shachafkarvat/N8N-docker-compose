# Reference to the existing NAT Gateway.
# ECS tasks in private subnets need internet access to:
#   - Pull docker.n8n.io/n8nio/n8n:stable on task startup
#   - Reach AWS SSM for secret injection (alternatively, use a VPC endpoint)
#   - Deliver logs to CloudWatch (alternatively, use a VPC endpoint)
#
# IMPORTANT: The private_subnet_ids you provide in terraform.tfvars MUST already
# have route table entries pointing to this NAT Gateway.
# If they do not, uncomment the route resources below.

data "aws_nat_gateway" "existing" {
  id = var.nat_gateway_id
}

# Uncomment if your private subnets do NOT already route through the NAT GW:
#
# data "aws_route_table" "private" {
#   for_each  = toset(var.private_subnet_ids)
#   subnet_id = each.value
# }
#
# resource "aws_route" "private_nat" {
#   for_each               = toset(var.private_subnet_ids)
#   route_table_id         = data.aws_route_table.private[each.value].id
#   destination_cidr_block = "0.0.0.0/0"
#   nat_gateway_id         = data.aws_nat_gateway.existing.id
# }
