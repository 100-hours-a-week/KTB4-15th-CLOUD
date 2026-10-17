output "cluster_arn" {
  description = "V2 prod ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_id" {
  description = "V2 prod ECS Cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "V2 prod ECS Cluster name"
  value       = aws_ecs_cluster.main.name
}
