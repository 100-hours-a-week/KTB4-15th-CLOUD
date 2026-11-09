# identity-api는 검증된 전신 이미지의 Presigned GET URL만 만든다.
data "aws_iam_policy_document" "identity_api_s3" {
  statement {
    sid     = "ReadBodyImages"
    actions = ["s3:GetObject"]
    resources = [
      "${local.images_bucket_arn}/body-images/*",
      "${local.images_bucket_arn}/users/*/body-images/*",
    ]
  }
}

resource "aws_iam_role_policy" "identity_api_s3" {
  name   = "${var.name_prefix}-identity-api-s3"
  role   = aws_iam_role.workload["identity-api"].id
  policy = data.aws_iam_policy_document.identity_api_s3.json
}

# body-image-validator는 검증된 이미지만 전신 이미지 Prefix에 저장한다.
data "aws_iam_policy_document" "body_image_validator_s3" {
  statement {
    sid       = "WriteBodyImages"
    actions   = ["s3:PutObject"]
    resources = ["${local.images_bucket_arn}/body-images/*"]
  }
}

resource "aws_iam_role_policy" "body_image_validator_s3" {
  name   = "${var.name_prefix}-body-image-validator-s3"
  role   = aws_iam_role.workload["body-image-validator"].id
  policy = data.aws_iam_policy_document.body_image_validator_s3.json
}

# fitting-api는 전신 이미지와 완료된 피팅 결과의 Presigned GET URL만 만든다.
data "aws_iam_policy_document" "fitting_api_s3" {
  statement {
    sid     = "ReadFittingImages"
    actions = ["s3:GetObject"]
    resources = [
      "${local.images_bucket_arn}/body-images/*",
      "${local.images_bucket_arn}/users/*/body-images/*",
      "${local.images_bucket_arn}/virtual-fitting/results/*",
    ]
  }
}

resource "aws_iam_role_policy" "fitting_api_s3" {
  name   = "${var.name_prefix}-fitting-api-s3"
  role   = aws_iam_role.workload["fitting-api"].id
  policy = data.aws_iam_policy_document.fitting_api_s3.json
}

# vton-orchestrator는 입력 이미지를 읽고 가상 피팅 결과 Prefix에만 기록한다.
data "aws_iam_policy_document" "vton_orchestrator_s3" {
  statement {
    sid     = "ReadFittingImages"
    actions = ["s3:GetObject"]
    resources = [
      "${local.images_bucket_arn}/body-images/*",
      "${local.images_bucket_arn}/users/*/body-images/*",
      "${local.images_bucket_arn}/virtual-fitting/results/*",
    ]
  }

  statement {
    sid       = "WriteFittingResults"
    actions   = ["s3:PutObject"]
    resources = ["${local.images_bucket_arn}/virtual-fitting/results/*"]
  }
}

resource "aws_iam_role_policy" "vton_orchestrator_s3" {
  name   = "${var.name_prefix}-vton-orchestrator-s3"
  role   = aws_iam_role.workload["vton-orchestrator"].id
  policy = data.aws_iam_policy_document.vton_orchestrator_s3.json
}
