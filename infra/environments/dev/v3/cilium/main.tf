# ---------------------------------------------------------------
# Cilium (CNI, ENI IPAM 모드)
# - 노드 그룹보다 먼저 설치한다. 노드가 없으므로 wait = false (Pod는 노드가 생기면 뜬다)
# - 값은 values.yaml.tftpl. 동적 값(API 엔드포인트, Operator IRSA Role)만 변수로 넣는다.
# ---------------------------------------------------------------
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.chart_version
  namespace  = "kube-system"

  wait    = false
  timeout = 600

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      k8s_service_host  = replace(var.cluster_endpoint, "https://", "")
      operator_role_arn = var.operator_role_arn
    })
  ]
}
