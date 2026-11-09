resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.irsa["ebs_csi_driver"].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
