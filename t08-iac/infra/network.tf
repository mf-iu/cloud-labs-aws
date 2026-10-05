# Network from lab t04: public, application and database subnets in two zones

locals {
  name = "${var.prefix}-${var.owner}"
  subnets = {
    public-a = { cidr = "10.20.0.0/24", zone = 0, tier = "public" }
    public-b = { cidr = "10.20.1.0/24", zone = 1, tier = "public" }
    app-a    = { cidr = "10.20.10.0/24", zone = 0, tier = "app" }
    app-b    = { cidr = "10.20.11.0/24", zone = 1, tier = "app" }
    db-a     = { cidr = "10.20.20.0/24", zone = 0, tier = "db" }
    db-b     = { cidr = "10.20.21.0/24", zone = 1, tier = "db" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = data.aws_availability_zones.available.names[each.value.zone]
  tags              = { Name = "${local.name}-${each.key}", tier = each.value.tier }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-public" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Application and database subnets only have the implicit local route
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-private" }
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = local.subnets[each.key].tier == "public" ? aws_route_table.public.id : aws_route_table.private.id
}
