removed {
  from = module.dev_v2_sqs

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v2_sqs

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_local_sqs

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_ecr

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_s3

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v1_monitoring.aws_sqs_queue.alert

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v1_monitoring.aws_sqs_queue.alert_dlq

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_iam.aws_iam_user.mq_local_test

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_iam.aws_iam_policy.mq_local_test

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_iam.aws_iam_user_policy_attachment.mq_local_test

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_repository.nextjs

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_lifecycle_policy.nextjs

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_repository.spring

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_lifecycle_policy.spring

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_repository.fastapi

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_lifecycle_policy.fastapi

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_repository.crawler

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.shared_core.aws_ecr_lifecycle_policy.crawler

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_versioning.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_server_side_encryption_configuration.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_public_access_block.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_ownership_controls.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_policy.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_s3.aws_s3_bucket_lifecycle_configuration.images

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_monitoring.aws_sqs_queue.lambda_promtail_failed

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v2_monitoring.aws_sqs_queue.lambda_promtail_failed

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_iam.aws_iam_policy.fastapi_sqs_fitting

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.dev_v2_iam.aws_iam_policy.spring_sqs_fitting

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v2_iam.aws_iam_policy.fastapi_sqs_fitting

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.prod_v2_iam.aws_iam_policy.spring_sqs_fitting

  lifecycle {
    destroy = false
  }
}
