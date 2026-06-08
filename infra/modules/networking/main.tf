data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Subnet CIDR math
# -----------------------------------------------------------------------------
# cidrsubnet(prefix, newbits, netnum) carves a /16 into /24s.
# - public  -> 10.0.0.0/24, 10.0.1.0/24
# - app     -> 10.0.10.0/24, 10.0.11.0/24
# - data    -> 10.0.20.0/24, 10.0.21.0/24
locals {
  public_cidrs = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  app_cidrs    = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  data_cidrs   = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}

# -----------------------------------------------------------------------------
# VPC + IGW
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # default true; needed for endpoint Private DNS
  enable_dns_hostnames = true # required for Private DNS resolution to work
  tags = {
    Name   = "${var.project}-vpc"
    Module = "networking"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

# -----------------------------------------------------------------------------
# Subnets (3 tiers x 2 AZs = 6 subnets)
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[each.value]
  availability_zone       = each.key
  map_public_ip_on_launch = false # never auto-assign public IPs in dev

  tags = {
    Name = "${var.project}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_cidrs[each.value]
  availability_zone = each.key

  tags = {
    Name = "${var.project}-private-app-${each.key}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "private_data" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[each.value]
  availability_zone = each.key

  tags = {
    Name = "${var.project}-private-data-${each.key}"
    Tier = "private-data"
  }
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------
# Public RT: default route to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-rt-public" }
}

resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private RT: NO default route. Egress only via VPC endpoints or (later) NAT GW.
# Shared across app + data tiers in dev. In prod we would split for blast-radius.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-rt-private" }
}

resource "aws_route_table_association" "private_app" {
  for_each       = aws_subnet.private_app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_data" {
  for_each       = aws_subnet.private_data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Gateway VPC endpoints (free) -- S3 + DynamoDB
# -----------------------------------------------------------------------------
# Attached to both route tables so anything in any subnet (public or private)
# routes S3 / DynamoDB traffic via the endpoint instead of IGW / future NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
  tags              = { Name = "${var.project}-vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
  tags              = { Name = "${var.project}-vpce-dynamodb" }
}

# -----------------------------------------------------------------------------
# Interface VPC endpoints (PAID -- toggle via var.interface_endpoints)
# -----------------------------------------------------------------------------
# Only create the security group if at least one interface endpoint is enabled,
# so dev cost stays at $0 by default.
resource "aws_security_group" "vpce" {
  count       = length(var.interface_endpoints) > 0 ? 1 : 0
  name        = "${var.project}-vpce-sg"
  description = "Allow HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from inside the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress (endpoint replies)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-vpce-sg" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private_app : s.id]
  security_group_ids  = [aws_security_group.vpce[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-vpce-${each.key}" }
}
