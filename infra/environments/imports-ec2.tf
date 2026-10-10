# V1 EC2 import targets.

import {
  to = module.prod_v1_compute.aws_instance.app_v1
  id = "i-0b4d0ff11e09efb6a"
}

import {
  to = module.prod_v1_compute.aws_eip.app_v1
  id = "eipalloc-0c80d06fa655797e5"
}

import {
  to = module.prod_v1_compute.aws_eip_association.app_v1
  id = "eipassoc-0e54a02e55b061f07"
}
