# V1 MySQL RDS import 블록.
# CI apply로 State에 등록한 뒤 별도 정리 PR에서 제거한다.

import {
  to = module.prod_v1_database.aws_db_subnet_group.mysql
  id = "lookddak-prod-db-subnet-group"
}

import {
  to = module.prod_v1_database.aws_db_parameter_group.mysql
  id = "lookddak-prod-mysql84-pg"
}

import {
  to = module.prod_v1_database.aws_db_instance.mysql
  id = "lookddak-prod-mysql"
}
