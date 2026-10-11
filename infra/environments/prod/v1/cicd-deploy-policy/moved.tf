# 배포 정책 3개를 for_each로 합치면서 바뀐 주소를 state에 반영한다.
# 적용(apply) 후에는 이 파일을 삭제한다.

moved {
  from = aws_iam_role_policy.fe_deploy
  to   = aws_iam_role_policy.deploy["fe"]
}

moved {
  from = aws_iam_role_policy.be_deploy
  to   = aws_iam_role_policy.deploy["be"]
}

moved {
  from = aws_iam_role_policy.ai_deploy
  to   = aws_iam_role_policy.deploy["ai"]
}
