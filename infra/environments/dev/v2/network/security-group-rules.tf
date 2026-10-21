# ---------------------------------------------------------------
# ALB
# Internet -> ALB -> Next.js / Spring
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.v2["alb"].id
  description       = "HTTP from internet for HTTPS redirect"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_internet" {
  security_group_id = aws_security_group.v2["alb"].id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nextjs" {
  security_group_id            = aws_security_group.v2["alb"].id
  description                  = "Next.js application traffic"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.v2["nextjs"].id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_spring" {
  security_group_id            = aws_security_group.v2["alb"].id
  description                  = "Spring API traffic"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.v2["spring"].id
}

# Temporary: ALB -> FastAPI for /api/v2/* (var.fastapi_alb_enabled)
resource "aws_vpc_security_group_egress_rule" "alb_to_fastapi" {
  count = var.fastapi_alb_enabled ? 1 : 0

  security_group_id            = aws_security_group.v2["alb"].id
  description                  = "FastAPI /api/v2 traffic (temporary)"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.v2["fastapi"].id
}

resource "aws_vpc_security_group_ingress_rule" "fastapi_from_alb" {
  count = var.fastapi_alb_enabled ? 1 : 0

  security_group_id            = aws_security_group.v2["fastapi"].id
  description                  = "FastAPI /api/v2 traffic from ALB (temporary)"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.v2["alb"].id
}

# ALB -> V1 dev EC2 nginx (dev.lookddak.com until the V2 cutover).
# The V1 app security group already allows 443 from the internet.
resource "aws_vpc_security_group_egress_rule" "alb_to_v1_dev_app" {
  security_group_id            = aws_security_group.v2["alb"].id
  description                  = "V1 dev nginx HTTPS traffic"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.dev_app_security_group_id
}

# ---------------------------------------------------------------
# Next.js
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "nextjs_from_alb" {
  security_group_id            = aws_security_group.v2["nextjs"].id
  description                  = "Application traffic from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.v2["alb"].id
}

resource "aws_vpc_security_group_egress_rule" "nextjs_to_spring" {
  security_group_id            = aws_security_group.v2["nextjs"].id
  description                  = "SSR API traffic to Spring through Service Connect"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.v2["spring"].id
}

# ---------------------------------------------------------------
# Spring
# ALB -> Spring -> MySQL / FastAPI
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "spring_from_alb" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "API traffic from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.v2["alb"].id
}

resource "aws_vpc_security_group_ingress_rule" "spring_from_nextjs" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "SSR API traffic from Next.js through Service Connect"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.v2["nextjs"].id
}

resource "aws_vpc_security_group_egress_rule" "spring_to_mysql" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "MySQL traffic to existing dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.dev_mysql_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_spring" {
  security_group_id            = var.dev_mysql_security_group_id
  description                  = "MySQL traffic from V2 Spring"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["spring"].id
}

resource "aws_vpc_security_group_egress_rule" "spring_to_fastapi" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "Internal API traffic to FastAPI"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.v2["fastapi"].id
}

# ---------------------------------------------------------------
# FastAPI
# Spring -> FastAPI -> PostgreSQL
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "fastapi_from_spring" {
  security_group_id            = aws_security_group.v2["fastapi"].id
  description                  = "Internal API traffic from Spring"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.v2["spring"].id
}

resource "aws_vpc_security_group_egress_rule" "fastapi_to_postgresql" {
  security_group_id            = aws_security_group.v2["fastapi"].id
  description                  = "PostgreSQL traffic"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# ---------------------------------------------------------------
# Crawler
# Crawler -> PostgreSQL
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "crawler_to_postgresql" {
  security_group_id            = aws_security_group.v2["crawler"].id
  description                  = "PostgreSQL traffic"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# ---------------------------------------------------------------
# PostgreSQL
# FastAPI, Crawler and V1 dev EC2 can initiate database connections.
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "postgresql_from_fastapi" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "PostgreSQL traffic from FastAPI"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["fastapi"].id
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_crawler" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "PostgreSQL traffic from crawler"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["crawler"].id
}

# V1 dev EC2 -> V2 PostgreSQL for DB inspection and rollback replication.
# Security groups are stateful; response traffic needs no reverse rules.
resource "aws_vpc_security_group_ingress_rule" "postgresql_from_v1_dev_app" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "PostgreSQL traffic from V1 dev EC2"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.dev_app_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "v1_dev_app_to_postgresql" {
  security_group_id            = var.dev_app_security_group_id
  description                  = "PostgreSQL traffic to V2 dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# V2 PostgreSQL -> V1 dev EC2 for forward logical replication.
# The RDS subscriber initiates the connection to the PostgreSQL publisher on EC2.
resource "aws_vpc_security_group_egress_rule" "postgresql_to_v1_dev_app" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "Logical replication to V1 dev PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.dev_app_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "v1_dev_app_from_postgresql" {
  security_group_id            = var.dev_app_security_group_id
  description                  = "Logical replication from V2 dev PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# ---------------------------------------------------------------
# MySQL (V1 MySQL migration target, read replica of the existing dev RDS)
# - V1 dev EC2 (ProxySQL) and V2 Spring connect to it after the cutover.
# - Replication between the existing dev RDS and V2 MySQL:
#   forward (existing -> V2) is opened by V2 MySQL, rollback (V2 -> existing)
#   is opened by the existing RDS, so each side needs its own egress rule.
#   Terraform-managed security groups have no default egress.
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "mysql_v2_from_v1_dev_app" {
  security_group_id            = aws_security_group.v2["mysql"].id
  description                  = "MySQL traffic from V1 dev EC2 (ProxySQL)"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.dev_app_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "v1_dev_app_to_mysql_v2" {
  security_group_id            = var.dev_app_security_group_id
  description                  = "MySQL traffic to V2 dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["mysql"].id
}

resource "aws_vpc_security_group_ingress_rule" "mysql_v2_from_spring" {
  security_group_id            = aws_security_group.v2["mysql"].id
  description                  = "MySQL traffic from V2 Spring"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["spring"].id
}

resource "aws_vpc_security_group_egress_rule" "spring_to_mysql_v2" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "MySQL traffic to V2 dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["mysql"].id
}

# Forward replication: V2 MySQL -> existing dev RDS
resource "aws_vpc_security_group_egress_rule" "mysql_v2_to_existing_mysql" {
  security_group_id            = aws_security_group.v2["mysql"].id
  description                  = "MySQL replication to existing dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.dev_mysql_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "existing_mysql_from_mysql_v2" {
  security_group_id            = var.dev_mysql_security_group_id
  description                  = "MySQL replication from V2 dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["mysql"].id
}

# Rollback replication: existing dev RDS -> V2 MySQL
resource "aws_vpc_security_group_egress_rule" "existing_mysql_to_mysql_v2" {
  security_group_id            = var.dev_mysql_security_group_id
  description                  = "MySQL rollback replication to V2 dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.v2["mysql"].id
}

resource "aws_vpc_security_group_ingress_rule" "mysql_v2_from_existing_mysql" {
  security_group_id            = aws_security_group.v2["mysql"].id
  description                  = "MySQL rollback replication from existing dev RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.dev_mysql_security_group_id
}

# ---------------------------------------------------------------
# ECS task outbound HTTPS
# - ECR image pull, Parameter Store, KMS and other AWS APIs
# - Spring/FastAPI SQS API path (IAM permissions are managed separately)
# - FastAPI external APIs and crawler target website
# Security groups cannot restrict HTTPS traffic by domain name.
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  for_each = toset(["nextjs", "spring", "fastapi", "crawler"])

  security_group_id = aws_security_group.v2[each.key].id
  description       = "HTTPS to AWS services and external APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
