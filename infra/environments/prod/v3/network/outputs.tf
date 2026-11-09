output "node_subnet_ids" {
  description = "EKS 노드·internal LB용 서브넷 ID (2a, 2c)"
  value       = [for key in sort(keys(aws_subnet.node)) : aws_subnet.node[key].id]
}

output "pod_subnet_ids" {
  description = "Pod 전용 서브넷 ID (2a, 2c)"
  value       = [for key in sort(keys(aws_subnet.pod)) : aws_subnet.pod[key].id]
}

output "pod_cidr_block" {
  description = "Pod 전용 보조 CIDR"
  value       = aws_vpc_ipv4_cidr_block_association.pod.cidr_block
}

output "private_route_table_id" {
  description = "node·Pod 서브넷 라우팅 테이블 ID"
  value       = aws_route_table.k8s_private.id
}
