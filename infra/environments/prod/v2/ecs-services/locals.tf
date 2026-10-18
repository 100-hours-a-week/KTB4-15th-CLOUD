locals {
  common_tags = {
    Environment = "prod"
    Version     = "v2"
    Component   = "ecs-service"
  }

  effective_service_capacity = {
    for service, capacity in var.service_capacity : service => {
      desired_count = var.activate_services ? capacity.desired_count : 0
      min_capacity  = var.activate_services ? capacity.min_capacity : 0
      max_capacity  = capacity.max_capacity
    }
  }
}
