# ---------------------------------------------------------------
# VPC
# ---------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "lookddak-prod-vpc"
    Environment = "prod"
  }
}

# ---------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lookddak-prod-public-a"
    Environment = "prod"
    Tier        = "public"
  }
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.11.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name        = "lookddak-prod-private-db-a"
    Environment = "prod"
    Tier        = "private-db"
  }
}

resource "aws_subnet" "private_db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.12.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name        = "lookddak-prod-private-db-c"
    Environment = "prod"
    Tier        = "private-db"
  }
}

# ---------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lookddak-prod-igw"
    Environment = "prod"
  }
}

# ---------------------------------------------------------------
# Route Table
# ---------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "lookddak-prod-public-rt"
    Environment = "prod"
    Tier        = "public"
  }
}

# DB 서브넷은 VPC 내부(local) 통신만 허용한다.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lookddak-prod-private-db-rt"
    Environment = "prod"
    Tier        = "private-db"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_db_a" {
  subnet_id      = aws_subnet.private_db_a.id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "private_db_c" {
  subnet_id      = aws_subnet.private_db_c.id
  route_table_id = aws_route_table.private_db.id
}
