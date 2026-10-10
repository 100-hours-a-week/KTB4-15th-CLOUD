import {
  to = module.prod_v1_parameter_store.aws_ssm_parameter.postgresql_database
  id = "/lookddak/prod/postgresql/database"
}

import {
  to = module.prod_v1_parameter_store.aws_ssm_parameter.postgresql_username
  id = "/lookddak/prod/postgresql/username"
}

import {
  to = module.prod_parameter_store.aws_ssm_parameter.rds_admin_username
  id = "/lookddak/prod/rds/admin/username"
}

import {
  to = module.prod_parameter_store.aws_ssm_parameter.rds_app_username
  id = "/lookddak/prod/rds/app/username"
}

import {
  to = module.prod_parameter_store.aws_ssm_parameter.rds_database
  id = "/lookddak/prod/rds/database"
}

import {
  to = module.prod_parameter_store.aws_ssm_parameter.rds_host
  id = "/lookddak/prod/rds/host"
}

import {
  to = module.prod_parameter_store.aws_ssm_parameter.rds_port
  id = "/lookddak/prod/rds/port"
}
