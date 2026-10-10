moved {
  from = module.prod_v1_iam.aws_iam_role_policy.fe_deploy
  to   = module.prod_v1_cicd_deploy_policy.aws_iam_role_policy.fe_deploy
}

moved {
  from = module.prod_v1_iam.aws_iam_role_policy.be_deploy
  to   = module.prod_v1_cicd_deploy_policy.aws_iam_role_policy.be_deploy
}

moved {
  from = module.prod_v1_iam.aws_iam_role_policy.ai_deploy
  to   = module.prod_v1_cicd_deploy_policy.aws_iam_role_policy.ai_deploy
}
