# EventBridge Role/Policy를 for_each로 합치면서 바뀐 주소를 state에 반영한다.
# 적용(apply) 후에는 이 파일을 삭제한다.

moved {
  from = aws_iam_role.eventbridge_alarm_state_change
  to   = aws_iam_role.eventbridge["alarm_state_change"]
}

moved {
  from = aws_iam_role.eventbridge_aws_health
  to   = aws_iam_role.eventbridge["aws_health"]
}

moved {
  from = aws_iam_role.eventbridge_docker_events
  to   = aws_iam_role.eventbridge["docker_events"]
}

moved {
  from = aws_iam_role.eventbridge_ec2_state_change
  to   = aws_iam_role.eventbridge["ec2_state_change"]
}

moved {
  from = aws_iam_role.eventbridge_rds_events
  to   = aws_iam_role.eventbridge["rds_events"]
}

moved {
  from = aws_iam_policy.eventbridge_alarm_state_change
  to   = aws_iam_policy.eventbridge["alarm_state_change"]
}

moved {
  from = aws_iam_policy.eventbridge_aws_health
  to   = aws_iam_policy.eventbridge["aws_health"]
}

moved {
  from = aws_iam_policy.eventbridge_docker_events
  to   = aws_iam_policy.eventbridge["docker_events"]
}

moved {
  from = aws_iam_policy.eventbridge_ec2_state_change
  to   = aws_iam_policy.eventbridge["ec2_state_change"]
}

moved {
  from = aws_iam_policy.eventbridge_rds_events
  to   = aws_iam_policy.eventbridge["rds_events"]
}

moved {
  from = aws_iam_role_policy_attachment.eventbridge_alarm_state_change
  to   = aws_iam_role_policy_attachment.eventbridge["alarm_state_change"]
}

moved {
  from = aws_iam_role_policy_attachment.eventbridge_aws_health
  to   = aws_iam_role_policy_attachment.eventbridge["aws_health"]
}

moved {
  from = aws_iam_role_policy_attachment.eventbridge_docker_events
  to   = aws_iam_role_policy_attachment.eventbridge["docker_events"]
}

moved {
  from = aws_iam_role_policy_attachment.eventbridge_ec2_state_change
  to   = aws_iam_role_policy_attachment.eventbridge["ec2_state_change"]
}

moved {
  from = aws_iam_role_policy_attachment.eventbridge_rds_events
  to   = aws_iam_role_policy_attachment.eventbridge["rds_events"]
}
