# ---------------------------------------------------------------
# AWS Load Balancer Controller
# - Istio Gateway의 Service(type: LoadBalancer)를 보고 내부 NLB(target-type ip)를 만든다.
# - 권한: LBC 공식 IAM 정책 (v3.6.2 docs/install/iam_policy.json) 원문 그대로 사용
#   차트 버전을 올릴 때 같은 태그의 정책 파일로 교체한다.
# ---------------------------------------------------------------
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.irsa["aws_load_balancer_controller"].id
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.2.json")
}
