# ---------------------------------------------------------------
# V1 dev 서버 보안 그룹
# - dev VPC(vpc.tf)에 만들며, dev app ↔ dev db만 서로 허용한다.
# - 보안 그룹끼리 서로 참조하므로 규칙은 별도 리소스로 관리한다.
# ---------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "lookddak-dev-app-sg"
  description = "LookDDak dev EC2 application security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "lookddak-dev-app-sg"
    Environment = "dev"
    Tier        = "app"
  }
}

resource "aws_security_group" "db" {
  name        = "lookddak-dev-db-sg"
  description = "LookDDak dev RDS MySQL security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "lookddak-dev-db-sg"
    Environment = "dev"
    Tier        = "db"
  }
}

# ---------------------------------------------------------------
# dev app-sg
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP redirect and Certbot"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS service"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "OS package repositories"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "AWS services and external APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_mysql_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "MySQL to dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.db.id
}

# ---------------------------------------------------------------
# dev db-sg
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from dev EC2"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}
