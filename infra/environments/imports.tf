# V1 리소스 import 블록
# apply로 state에 편입된 뒤에는 이 블록들을 삭제해도 된다.

# ---------------------------------------------------------------
# VPC
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_vpc.main
  id = "vpc-00846a80381ac4f45" # lookddak-prod-vpc
}

# ---------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_subnet.public_a
  id = "subnet-08fa8e8ae3807add5" # lookddak-prod-public-a
}

import {
  to = module.shared_core.aws_subnet.private_db_a
  id = "subnet-0c5c65cadc147471a" # lookddak-prod-private-db-a
}

import {
  to = module.shared_core.aws_subnet.private_db_c
  id = "subnet-0656a2f1edaa3e60d" # lookddak-prod-private-db-c
}

# ---------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_internet_gateway.main
  id = "igw-0ffce181f07088953"
}

# ---------------------------------------------------------------
# Route Table
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_route_table.public
  id = "rtb-0afd483720fd18f15" # lookddak-prod-public-rt
}

import {
  to = module.shared_core.aws_route_table.private_db
  id = "rtb-0ac62a8c3c1d739fa" # lookddak-prod-private-db-rt
}

# ---------------------------------------------------------------
# Route Table Association (id 형식: 서브넷ID/라우트테이블ID)
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_route_table_association.public_a
  id = "subnet-08fa8e8ae3807add5/rtb-0afd483720fd18f15"
}

import {
  to = module.shared_core.aws_route_table_association.private_db_a
  id = "subnet-0c5c65cadc147471a/rtb-0ac62a8c3c1d739fa"
}

import {
  to = module.shared_core.aws_route_table_association.private_db_c
  id = "subnet-0656a2f1edaa3e60d/rtb-0ac62a8c3c1d739fa"
}

# ---------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_security_group.app
  id = "sg-0dbfed983b348ab30" # lookddak-prod-app-sg
}

import {
  to = module.shared_core.aws_security_group.db
  id = "sg-025058aa2a343da10" # lookddak-prod-db-sg
}

import {
  to = module.shared_core.aws_security_group.crawler
  id = "sg-0016ac152c135f51c" # lookddak-prod-crawler-sg
}

# ---------------------------------------------------------------
# Security Group Rule
# 보안그룹끼리 서로 참조하므로(app <-> db, app <-> crawler)
# 규칙을 보안그룹 안에 넣으면 순환 참조가 생긴다. 규칙은 별도 리소스로 관리한다.
# ---------------------------------------------------------------

# app-sg ingress
import {
  to = module.shared_core.aws_vpc_security_group_ingress_rule.app_http
  id = "sgr-035725c766c864096" # 80 from 0.0.0.0/0
}

import {
  to = module.shared_core.aws_vpc_security_group_ingress_rule.app_https
  id = "sgr-05fa184411d4ba9d9" # 443 from 0.0.0.0/0
}

import {
  to = module.shared_core.aws_vpc_security_group_ingress_rule.app_postgres_from_crawler
  id = "sgr-0a37839b5f5aa6ca2" # 5432 from crawler-sg
}

# app-sg egress
import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.app_http
  id = "sgr-0761819e55347ff93" # 80 to 0.0.0.0/0
}

import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.app_https
  id = "sgr-0e25f8fd91a2763ea" # 443 to 0.0.0.0/0
}

import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.app_mysql_to_db
  id = "sgr-0f953e155acd947bd" # 3306 to db-sg
}

# db-sg ingress
import {
  to = module.shared_core.aws_vpc_security_group_ingress_rule.db_mysql_from_app
  id = "sgr-0af1dbd810f60cb86" # 3306 from app-sg
}

# crawler-sg egress
import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.crawler_postgres_to_app
  id = "sgr-0f1467894eb9a6ea3" # 5432 to app-sg
}

import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.crawler_http
  id = "sgr-0a62216a6b5933f66" # 80 to 0.0.0.0/0
}

import {
  to = module.shared_core.aws_vpc_security_group_egress_rule.crawler_https
  id = "sgr-0c918b73ee26acd7e" # 443 to 0.0.0.0/0
}
