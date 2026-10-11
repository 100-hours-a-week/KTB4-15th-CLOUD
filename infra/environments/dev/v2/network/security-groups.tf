# ---------------------------------------------------------------
# V2 dev security group shells
# - Detailed ingress/egress rules are managed in the next security group issue.
# - Keeping the groups here lets later modules depend on stable IDs.
# ---------------------------------------------------------------
locals {
  security_groups = {
    alb = {
      name        = "lookddak-dev-v2-alb-sg"
      description = "LookDDak dev V2 ALB security group"
      tier        = "load-balancer"
    }
    nextjs = {
      name        = "lookddak-dev-v2-nextjs-sg"
      description = "LookDDak dev V2 Next.js security group"
      tier        = "app"
    }
    spring = {
      name        = "lookddak-dev-v2-spring-sg"
      description = "LookDDak dev V2 Spring security group"
      tier        = "app"
    }
    fastapi = {
      name        = "lookddak-dev-v2-fastapi-sg"
      description = "LookDDak dev V2 FastAPI security group"
      tier        = "app"
    }
    crawler = {
      name        = "lookddak-dev-v2-crawler-sg"
      description = "LookDDak dev V2 crawler security group"
      tier        = "app"
    }
    postgresql = {
      name        = "lookddak-dev-v2-postgresql-sg"
      description = "LookDDak dev V2 PostgreSQL security group"
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
    Environment = "dev"
    Version     = "v2"
    Tier        = each.value.tier
  }
}
