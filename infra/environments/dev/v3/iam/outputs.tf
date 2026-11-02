output "cilium_operator_role_arn" {
  description = "cilium-operator ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["cilium_operator"].arn
}
