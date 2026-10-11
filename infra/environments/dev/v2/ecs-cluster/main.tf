resource "aws_ecs_cluster" "main" {
  name = "lookddak-dev-v2"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = "dev"
    Version     = "v2"
  }
}
