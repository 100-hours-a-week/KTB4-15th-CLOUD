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

resource "aws_vpc_security_group_egress_rule" "alb_to_spring_sse" {
  security_group_id            = aws_security_group.v2["alb"].id
  description                  = "Spring notification SSE traffic"
  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
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

resource "aws_vpc_security_group_ingress_rule" "spring_sse_from_alb" {
  security_group_id            = aws_security_group.v2["spring"].id
  description                  = "Notification SSE traffic from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
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
# FastAPI and Crawler can initiate database connections.
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

# ---------------------------------------------------------------
# MySQL
# V2 Spring connects to the V2 MySQL database after cutover.
# ---------------------------------------------------------------
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
