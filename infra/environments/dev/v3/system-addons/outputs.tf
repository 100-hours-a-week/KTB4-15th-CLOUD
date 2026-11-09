output "coredns_addon_arn" {
  description = "CoreDNS EKS Add-on ARN"
  value       = aws_eks_addon.coredns.arn
}

output "coredns_addon_version" {
  description = "설치된 CoreDNS EKS Add-on 버전"
  value       = aws_eks_addon.coredns.addon_version
}

output "ebs_csi_driver_addon_version" {
  description = "설치된 EBS CSI Driver EKS Add-on 버전"
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}
