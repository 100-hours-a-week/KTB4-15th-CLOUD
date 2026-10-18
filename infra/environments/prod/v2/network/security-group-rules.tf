# ---------------------------------------------------------------
# ALB
# CloudFront -> ALB -> Next.js / Spring
# ---------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_cloudfront" {
  security_group_id = aws_security_group.v2["alb"].id
  description       = "HTTPS from CloudFront origin-facing servers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
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
# ALB / Next.js -> Spring -> FastAPI
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
# FastAPI, Crawler, and V1 prod EC2 can initiate database connections.
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

# V1 prod EC2 -> V2 PostgreSQL for DB inspection and rollback replication.
# Security groups are stateful; response traffic needs no reverse rules.
resource "aws_vpc_security_group_ingress_rule" "postgresql_from_v1_prod_app" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "PostgreSQL traffic from V1 prod EC2"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.prod_app_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "v1_prod_app_to_postgresql" {
  security_group_id            = var.prod_app_security_group_id
  description                  = "PostgreSQL traffic to V2 prod RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# V2 PostgreSQL -> V1 prod EC2 for forward logical replication.
# The RDS subscriber initiates the connection to the PostgreSQL publisher on EC2.
resource "aws_vpc_security_group_egress_rule" "postgresql_to_v1_prod_app" {
  security_group_id            = aws_security_group.v2["postgresql"].id
  description                  = "Logical replication to V1 prod PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.prod_app_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "v1_prod_app_from_postgresql" {
  security_group_id            = var.prod_app_security_group_id
  description                  = "Logical replication from V2 prod PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.v2["postgresql"].id
}

# ---------------------------------------------------------------
# ECS task outbound HTTPS
# - ECR image pull, Parameter Store, KMS, SQS, and other AWS APIs
# - FastAPI external APIs and crawler target websites
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
