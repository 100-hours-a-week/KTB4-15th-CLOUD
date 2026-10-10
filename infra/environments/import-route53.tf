# Route53 import 블록
# apply로 state에 편입된 뒤에는 이 파일을 삭제한다.
# 레코드 id 형식: <Zone ID>_<레코드 이름>_<타입>

# ---------------------------------------------------------------
# shared/core
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_route53_zone.main
  id = "Z06877251U6DKTWG3X2JG" # lookddak.com
}

import {
  to = module.shared_core.aws_route53_record.mx
  id = "Z06877251U6DKTWG3X2JG_lookddak.com_MX"
}

import {
  to = module.shared_core.aws_route53_record.spf
  id = "Z06877251U6DKTWG3X2JG_lookddak.com_TXT"
}

# ---------------------------------------------------------------
# prod/v1/edge
# ---------------------------------------------------------------
import {
  to = module.prod_v1_edge.aws_route53_record.apex
  id = "Z06877251U6DKTWG3X2JG_lookddak.com_A"
}

import {
  to = module.prod_v1_edge.aws_route53_record.www
  id = "Z06877251U6DKTWG3X2JG_www.lookddak.com_CNAME"
}
