# ---------------------------------------------------------------
# V2 prod security groups
# - Rules are managed separately in security-group-rules.tf.
# - MySQL security groups and rules are outside this work scope.
# ---------------------------------------------------------------
locals {
  security_groups = {
    alb = {
      name        = "lookddak-prod-v2-alb-sg"
      description = "LookDDak prod V2 ALB security group"
      tier        = "load-balancer"
    }
    nextjs = {
      name        = "lookddak-prod-v2-nextjs-sg"
      description = "LookDDak prod V2 Next.js security group"
      tier        = "app"
    }
    spring = {
      name        = "lookddak-prod-v2-spring-sg"
      description = "LookDDak prod V2 Spring security group"
      tier        = "app"
    }
    fastapi = {
      name        = "lookddak-prod-v2-fastapi-sg"
      description = "LookDDak prod V2 FastAPI security group"
      tier        = "app"
    }
    crawler = {
      name        = "lookddak-prod-v2-crawler-sg"
      description = "LookDDak prod V2 crawler security group"
      tier        = "app"
    }
    postgresql = {
      name        = "lookddak-prod-v2-postgresql-sg"
      description = "LookDDak prod V2 PostgreSQL security group"
      tier        = "db"
    }
  }
}

resource "aws_security_group" "v2" {
  for_each = local.security_groups

  name                   = each.value.name
  description            = each.value.description
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Name        = each.value.name
    Environment = "prod"
    Version     = "v2"
    Tier        = each.value.tier
  }
}
