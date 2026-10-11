# ---------------------------------------------------------------
# Existing dev network lookup
# - V1 dev owns the VPC and Internet Gateway.
# - V2 only reads them and creates its own subnets and route tables.
# ---------------------------------------------------------------
data "aws_internet_gateway" "dev" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# ---------------------------------------------------------------
# Public subnet (ALB / NAT Gateway)
# ---------------------------------------------------------------
resource "aws_subnet" "public_c" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.30.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lookddak-dev-v2-public-c"
    Environment = "dev"
    Version     = "v2"
    Tier        = "public"
  }
}

resource "aws_route_table" "public_c" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.dev.id
  }

  tags = {
    Name        = "lookddak-dev-v2-public-c-rt"
    Environment = "dev"
    Version     = "v2"
    Tier        = "public"
  }
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public_c.id
}

# ---------------------------------------------------------------
# NAT Gateway (single AZ for the rehearsal/staging environment)
# ---------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "lookddak-dev-v2-nat-eip"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_c.id

  tags = {
    Name        = "lookddak-dev-v2-nat"
    Environment = "dev"
    Version     = "v2"
  }

  depends_on = [aws_route_table_association.public_c]
}

# ---------------------------------------------------------------
# Private application subnets (ECS Fargate)
# ---------------------------------------------------------------
resource "aws_subnet" "private_app_a" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.30.21.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "lookddak-dev-v2-private-app-a"
    Environment = "dev"
    Version     = "v2"
    Tier        = "private-app"
  }
}

resource "aws_subnet" "private_app_c" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.30.22.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name        = "lookddak-dev-v2-private-app-c"
    Environment = "dev"
    Version     = "v2"
    Tier        = "private-app"
  }
}

resource "aws_route_table" "private_app" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "lookddak-dev-v2-private-app-rt"
    Environment = "dev"
    Version     = "v2"
    Tier        = "private-app"
  }
}

resource "aws_route_table_association" "private_app_a" {
  subnet_id      = aws_subnet.private_app_a.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_app_c" {
  subnet_id      = aws_subnet.private_app_c.id
  route_table_id = aws_route_table.private_app.id
}
