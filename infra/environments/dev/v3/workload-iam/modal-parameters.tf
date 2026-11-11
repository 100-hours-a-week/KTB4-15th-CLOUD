locals {
  idm_vton_modal_parameter_names = {
    token_id     = "/lookddak/dev/fastapi/idm-vton/modal-token-id"
    token_secret = "/lookddak/dev/fastapi/idm-vton/modal-token-secret"
  }
}

# Modal Python SDK가 IDM-VTON fallback을 호출할 때 사용하는 인증 경로다.
# 실제 Token은 Terraform 밖에서 입력하며, write-only 초기값은 State에 저장하지 않는다.
resource "aws_ssm_parameter" "idm_vton_modal" {
  for_each = local.idm_vton_modal_parameter_names

  name        = each.value
  description = "LookDDak Dev IDM-VTON Modal SDK ${replace(each.key, "_", " ")} (replace before workload wiring)"
  type        = "SecureString"
  key_id      = data.aws_kms_alias.ssm.target_key_arn
  tier        = "Standard"
  data_type   = "text"

  value_wo         = "PENDING_MANUAL_CONFIGURATION"
  value_wo_version = 1

  tags = merge(local.common_tags, {
    CredentialType = "modal-sdk"
    Workload       = "vton-orchestrator"
  })

  lifecycle {
    prevent_destroy = true
  }
}
