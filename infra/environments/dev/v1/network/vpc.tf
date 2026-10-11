# ---------------------------------------------------------------
# V1 dev 전용 VPC
# - prod VPC(shared/core, 10.20.0.0/16)와 네트워크를 분리한다.
# - 구조는 prod와 같다: public 서브넷 1개(EC2), private DB 서브넷 2개(RDS, 2개 AZ 필수)
# - CIDR을 prod와 겹치지 않게 잡아, 필요 시 VPC Peering이 가능하도록 한다.
# - NAT Gateway는 두지 않는다 (DB 서브넷은 VPC 내부 통신만 사용).
# ---------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "lookddak-dev-vpc"
    Environment = "dev"
  }
}

# ---------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.30.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lookddak-dev-public-a"
    Environment = "dev"
    Tier        = "public"
  }
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.30.11.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name        = "lookddak-dev-private-db-a"
    Environment = "dev"
    Tier        = "private-db"
  }
}

resource "aws_subnet" "private_db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.30.12.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name        = "lookddak-dev-private-db-c"
    Environment = "dev"
    Tier        = "private-db"
  }
}

# ---------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lookddak-dev-igw"
    Environment = "dev"
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
    Name        = "lookddak-dev-public-rt"
    Environment = "dev"
    Tier        = "public"
  }
}

# DB 서브넷은 VPC 내부(local) 통신만 허용한다.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lookddak-dev-private-db-rt"
    Environment = "dev"
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
