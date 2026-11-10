output "cilium_operator_role_arn" {
  description = "cilium-operator ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["cilium_operator"].arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "kube-system/aws-load-balancer-controller ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["aws_load_balancer_controller"].arn
}

output "cert_manager_role_arn" {
  description = "kube-system/cert-manager ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["cert_manager"].arn
}

output "ebs_csi_driver_role_arn" {
  description = "kube-system/ebs-csi-controller-sa ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["ebs_csi_driver"].arn
}

output "argocd_notifications_role_arn" {
  description = "argocd/argocd-notifications-controller ServiceAccount에 붙일 IRSA Role ARN"
  value       = aws_iam_role.irsa["argocd_notifications"].arn
}
