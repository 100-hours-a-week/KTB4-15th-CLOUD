resource "aws_ecs_cluster" "main" {
  name = "lookddak-prod-v2"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = "prod"
    Version     = "v2"
  }
}
