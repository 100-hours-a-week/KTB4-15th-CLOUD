output "alb_public_subnet_ids" {
  description = "V2 ALB가 사용할 기존 Public 2a와 신규 Public 2c 서브넷 ID"
  value       = [var.existing_public_subnet_id, aws_subnet.public_c.id]
}

output "private_app_subnet_ids" {
  description = "V2 ECS Task가 사용할 Private App 2a/2c 서브넷 ID"
  value       = [aws_subnet.private_app_a.id, aws_subnet.private_app_c.id]
}

output "nat_gateway_id" {
  description = "V2 Private App 서브넷의 단일 NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "public_c_subnet_id" {
  description = "V2 Prod Public 2c 서브넷 ID"
  value       = aws_subnet.public_c.id
}

output "private_app_route_table_id" {
  description = "V2 Prod Private App 공용 Route Table ID"
  value       = aws_route_table.private_app.id
}
