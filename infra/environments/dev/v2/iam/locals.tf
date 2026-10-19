data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  task_services = toset(["nextjs", "spring", "fastapi", "crawler"])

  dev_image_bucket_arn                = "arn:${local.partition}:s3:::lookddak-dev-images-${local.account_id}-${local.region}"
  dev_fastapi_parameter_arn_pattern   = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/fastapi/*"
  dev_internal_parameter_arn_pattern  = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/internal/*"
  dev_rds_app_parameter_arn_pattern   = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/rds/app/*"
  dev_spring_parameter_arn_pattern    = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/spring/*"
  dev_v2_parameter_arn_pattern        = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/v2/*"
  ecr_repository_arn_pattern          = "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/lookddak-*"
  crawler_task_definition_arn_pattern = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/lookddak-dev-v2-crawler:*"
  crawler_schedule_group_arn          = "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule-group/lookddak-dev-v2"

  shared_test_legacy_log_group_names = toset([
    "/lookddak/dev/fastapi",
    "/lookddak/dev/nextjs",
    "/lookddak/dev/nginx",
    "/lookddak/dev/postgresql",
    "/lookddak/dev/spring",
    "/lookddak/prod/fastapi",
    "/lookddak/prod/nextjs",
    "/lookddak/prod/nginx",
    "/lookddak/prod/postgresql",
    "/lookddak/prod/spring",
  ])
  shared_test_log_group_arns = concat(
    var.log_group_arns,
    [
      for name in local.shared_test_legacy_log_group_names :
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${name}"
    ],
  )

  ecs_tasks_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  scheduler_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = local.crawler_schedule_group_arn
        }
      }
    }]
  })
}
