# Public networking for an existing VPC.
#
# If public_subnet_ids are supplied, the module reuses them.
# If not, it creates public subnets, an Internet Gateway, and a shared
# public route table in the target VPC.

resource "aws_internet_gateway" "public" {
  count  = var.internet_gateway_id == null ? 1 : 0
  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "n8n-igw" })
}

resource "aws_subnet" "public" {
  for_each = length(var.public_subnet_ids) == 0 ? local.created_public_subnets : {}

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "n8n-public-${each.value.az}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  count  = length(var.public_subnet_ids) == 0 ? 1 : 0
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.effective_internet_gateway_id
  }

  tags = merge(local.tags, { Name = "n8n-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}