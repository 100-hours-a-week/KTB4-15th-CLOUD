# RDS 리소스를 modules/rds-mysql로 옮기면서 바뀐 주소를 state에 반영한다.
# 적용(apply) 후에는 이 파일을 삭제한다.

moved {
  from = aws_db_subnet_group.mysql
  to   = module.mysql.aws_db_subnet_group.this
}

moved {
  from = aws_db_parameter_group.mysql
  to   = module.mysql.aws_db_parameter_group.this
}

moved {
  from = aws_db_instance.mysql
  to   = module.mysql.aws_db_instance.this
}
