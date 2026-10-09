# 보안그룹끼리 서로 참조하므로(app <-> db, app <-> crawler)
# 규칙은 보안그룹 안에 넣지 않고 별도 리소스로 관리한다.

# ---------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "lookddak-prod-app-sg"
  description = "LookDDak production EC2 application security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "lookddak-prod-app-sg"
    Environment = "prod"
    Tier        = "app"
  }
}

resource "aws_security_group" "db" {
  name        = "lookddak-prod-db-sg"
  description = "LookDDak production RDS MySQL security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "lookddak-prod-db-sg"
    Environment = "prod"
    Tier        = "db"
  }
}

resource "aws_security_group" "crawler" {
  name        = "lookddak-prod-crawler-sg"
  description = "LookDDak production Fargate crawler security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "lookddak-prod-crawler-sg"
    Environment = "prod"
    Tier        = "crawler"
  }
}

# ---------------------------------------------------------------
# app-sg
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

resource "aws_vpc_security_group_ingress_rule" "app_postgres_from_crawler" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL from Fargate crawler"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.crawler.id
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
  description                  = "MySQL to RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.db.id
}

# ---------------------------------------------------------------
# db-sg
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from Spring Boot EC2"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}

# ---------------------------------------------------------------
# crawler-sg
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "crawler_http" {
  security_group_id = aws_security_group.crawler.id
  description       = "HTTP crawling"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "crawler_https" {
  security_group_id = aws_security_group.crawler.id
  description       = "HTTPS crawling and AWS services"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "crawler_postgres_to_app" {
  security_group_id            = aws_security_group.crawler.id
  description                  = "PostgreSQL on EC2"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
