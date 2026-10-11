# prod 네트워크를 shared/core → prod/v1/network로 옮기면서 바뀐 주소를 state에 반영한다.
# 적용(apply) 후에는 이 파일을 삭제한다.

moved {
  from = module.shared_core.aws_vpc.main
  to   = module.prod_v1_network.aws_vpc.main
}

moved {
  from = module.shared_core.aws_subnet.public_a
  to   = module.prod_v1_network.aws_subnet.public_a
}

moved {
  from = module.shared_core.aws_subnet.private_db_a
  to   = module.prod_v1_network.aws_subnet.private_db_a
}

moved {
  from = module.shared_core.aws_subnet.private_db_c
  to   = module.prod_v1_network.aws_subnet.private_db_c
}

moved {
  from = module.shared_core.aws_internet_gateway.main
  to   = module.prod_v1_network.aws_internet_gateway.main
}

moved {
  from = module.shared_core.aws_route_table.public
  to   = module.prod_v1_network.aws_route_table.public
}

moved {
  from = module.shared_core.aws_route_table.private_db
  to   = module.prod_v1_network.aws_route_table.private_db
}

moved {
  from = module.shared_core.aws_route_table_association.public_a
  to   = module.prod_v1_network.aws_route_table_association.public_a
}

moved {
  from = module.shared_core.aws_route_table_association.private_db_a
  to   = module.prod_v1_network.aws_route_table_association.private_db_a
}

moved {
  from = module.shared_core.aws_route_table_association.private_db_c
  to   = module.prod_v1_network.aws_route_table_association.private_db_c
}

moved {
  from = module.shared_core.aws_security_group.app
  to   = module.prod_v1_network.aws_security_group.app
}

moved {
  from = module.shared_core.aws_security_group.db
  to   = module.prod_v1_network.aws_security_group.db
}

moved {
  from = module.shared_core.aws_vpc_security_group_ingress_rule.app_http
  to   = module.prod_v1_network.aws_vpc_security_group_ingress_rule.app_http
}

moved {
  from = module.shared_core.aws_vpc_security_group_ingress_rule.app_https
  to   = module.prod_v1_network.aws_vpc_security_group_ingress_rule.app_https
}

moved {
  from = module.shared_core.aws_vpc_security_group_egress_rule.app_http
  to   = module.prod_v1_network.aws_vpc_security_group_egress_rule.app_http
}

moved {
  from = module.shared_core.aws_vpc_security_group_egress_rule.app_https
  to   = module.prod_v1_network.aws_vpc_security_group_egress_rule.app_https
}

moved {
  from = module.shared_core.aws_vpc_security_group_egress_rule.app_mysql_to_db
  to   = module.prod_v1_network.aws_vpc_security_group_egress_rule.app_mysql_to_db
}

moved {
  from = module.shared_core.aws_vpc_security_group_ingress_rule.db_mysql_from_app
  to   = module.prod_v1_network.aws_vpc_security_group_ingress_rule.db_mysql_from_app
}
