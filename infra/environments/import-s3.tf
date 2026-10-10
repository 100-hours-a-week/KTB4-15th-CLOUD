# S3 import 블록
# apply로 state에 편입된 뒤에는 이 파일을 삭제한다.

# ---------------------------------------------------------------
# prod_s3 (lookddak-prod-images-686496667254-ap-northeast-2)
# ---------------------------------------------------------------
import {
  to = module.prod_s3.aws_s3_bucket.images
  id = "lookddak-prod-images-686496667254-ap-northeast-2"
}

import {
  to = module.prod_s3.aws_s3_bucket_server_side_encryption_configuration.images
  id = "lookddak-prod-images-686496667254-ap-northeast-2"
}

import {
  to = module.prod_s3.aws_s3_bucket_public_access_block.images
  id = "lookddak-prod-images-686496667254-ap-northeast-2"
}

import {
  to = module.prod_s3.aws_s3_bucket_ownership_controls.images
  id = "lookddak-prod-images-686496667254-ap-northeast-2"
}

import {
  to = module.prod_s3.aws_s3_bucket_policy.images
  id = "lookddak-prod-images-686496667254-ap-northeast-2"
}

# ---------------------------------------------------------------
# dev_s3 (lookddak-dev-images-686496667254-ap-northeast-2)
# ---------------------------------------------------------------
import {
  to = module.dev_s3.aws_s3_bucket.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}

import {
  to = module.dev_s3.aws_s3_bucket_server_side_encryption_configuration.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}

import {
  to = module.dev_s3.aws_s3_bucket_public_access_block.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}

import {
  to = module.dev_s3.aws_s3_bucket_ownership_controls.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}

import {
  to = module.dev_s3.aws_s3_bucket_policy.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}

import {
  to = module.dev_s3.aws_s3_bucket_lifecycle_configuration.images
  id = "lookddak-dev-images-686496667254-ap-northeast-2"
}
