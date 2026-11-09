data "aws_iam_policy_document" "assume" {
  for_each = local.irsa

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.irsa

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json

  tags = merge(local.common_tags, {
    Name           = "${var.name_prefix}-${each.key}"
    ServiceAccount = "${local.namespace}/${each.value.service_account}"
  })
}

data "aws_iam_policy_document" "bucket" {
  for_each = local.buckets

  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this[each.key].arn]
  }

  statement {
    sid = "ReadWriteObjects"
    actions = concat(
      ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      each.key == "tempo" ? ["s3:GetObjectTagging", "s3:PutObjectTagging"] : [],
    )
    resources = ["${aws_s3_bucket.this[each.key].arn}/*"]
  }
}

resource "aws_iam_role_policy" "bucket" {
  for_each = local.buckets

  name   = "${var.name_prefix}-${each.key}-s3"
  role   = aws_iam_role.this[each.key].id
  policy = data.aws_iam_policy_document.bucket[each.key].json
}

data "aws_iam_policy_document" "db_log_tailer" {
  statement {
    sid = "ReadRdsLogFiles"
    actions = [
      "rds:DescribeDBLogFiles",
      "rds:DownloadDBLogFilePortion",
    ]
    resources = [
      for id in var.db_log_instance_ids :
      "arn:${local.partition}:rds:${local.region}:${local.account_id}:db:${id}"
    ]
  }
}

resource "aws_iam_role_policy" "db_log_tailer" {
  name   = "${var.name_prefix}-db-log-tailer-rds-logs"
  role   = aws_iam_role.this["db-log-tailer"].id
  policy = data.aws_iam_policy_document.db_log_tailer.json
}
