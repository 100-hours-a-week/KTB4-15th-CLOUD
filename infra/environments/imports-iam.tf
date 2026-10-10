# V1 IAM import targets.

# V1 EC2 IAM
import {
  to = module.prod_v1_iam.aws_iam_role.ec2
  id = "ec2-ssm"
}

import {
  to = module.prod_v1_iam.aws_iam_instance_profile.ec2
  id = "ec2-ssm"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.ec2_ssm_core
  id = "arn:aws:iam::686496667254:policy/lookddak-prod-ec2-ssm-core"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.ec2_ecr_pull
  id = "arn:aws:iam::686496667254:policy/lookddak-prod-ec2-ecr-pull"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.ec2_cloudwatch_logs_write
  id = "arn:aws:iam::686496667254:policy/lookddak-prod-ec2-cloudwatch-logs-write"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.ec2_parameters_read
  id = "arn:aws:iam::686496667254:policy/lookddak-prod-ec2-parameters-read"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.ec2_s3_images_rw
  id = "arn:aws:iam::686496667254:policy/lookddak-prod-ec2-s3-images-rw"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.ec2_ssm_core
  id = "ec2-ssm/arn:aws:iam::686496667254:policy/lookddak-prod-ec2-ssm-core"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.ec2_ecr_pull
  id = "ec2-ssm/arn:aws:iam::686496667254:policy/lookddak-prod-ec2-ecr-pull"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.ec2_cloudwatch_logs_write
  id = "ec2-ssm/arn:aws:iam::686496667254:policy/lookddak-prod-ec2-cloudwatch-logs-write"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.ec2_parameters_read
  id = "ec2-ssm/arn:aws:iam::686496667254:policy/lookddak-prod-ec2-parameters-read"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.ec2_s3_images_rw
  id = "ec2-ssm/arn:aws:iam::686496667254:policy/lookddak-prod-ec2-s3-images-rw"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.ec2_eventbridge_write
  id = "ec2-ssm:log-eventBridge-write-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.ec2_status_log_write
  id = "ec2-ssm:lookddak-alert-status-log"
}

# GitHub Actions application CI/CD IAM
import {
  to = module.prod_v1_iam.aws_iam_role.fe_build
  id = "fe-cd-build-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role.fe_deploy
  id = "fe-cd-deploy-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role.be_build
  id = "be-cd-build-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role.be_deploy
  id = "be-cd-deploy-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role.ai_build
  id = "ai-cd-build-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role.ai_deploy
  id = "ai-cd-deploy-role"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.fe_build
  id = "fe-cd-build-role:fe-cd-build-rolePolicy"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.fe_deploy
  id = "fe-cd-deploy-role:fe-cd-deploy-rolePolicy"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.be_build
  id = "be-cd-build-role:be-cd-build-rolePolicy"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.be_deploy
  id = "be-cd-deploy-role:be-cd-deploy-rolePolicy"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.ai_build
  id = "ai-cd-build-role:ai-cd-build-rolePolicy"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.ai_deploy
  id = "ai-cd-deploy-role:ai-cd-deploy-rolePolicy"
}

# Monitoring IAM: EventBridge to SQS
import {
  to = module.prod_v1_iam.aws_iam_role.eventbridge_alarm_state_change
  id = "Amazon_EventBridge_Invoke_Sqs_1504746143"
}

import {
  to = module.prod_v1_iam.aws_iam_role.eventbridge_ec2_state_change
  id = "Amazon_EventBridge_Invoke_Sqs_1541928649"
}

import {
  to = module.prod_v1_iam.aws_iam_role.eventbridge_aws_health
  id = "Amazon_EventBridge_Invoke_Sqs_1568336830"
}

import {
  to = module.prod_v1_iam.aws_iam_role.eventbridge_docker_events
  id = "Amazon_EventBridge_Invoke_Sqs_2071571937"
}

import {
  to = module.prod_v1_iam.aws_iam_role.eventbridge_rds_events
  id = "Amazon_EventBridge_Invoke_Sqs_533425366"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.eventbridge_alarm_state_change
  id = "arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1504746143"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.eventbridge_ec2_state_change
  id = "arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1541928649"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.eventbridge_aws_health
  id = "arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1568336830"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.eventbridge_docker_events
  id = "arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_2071571937"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.eventbridge_rds_events
  id = "arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_533425366"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.eventbridge_alarm_state_change
  id = "Amazon_EventBridge_Invoke_Sqs_1504746143/arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1504746143"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.eventbridge_ec2_state_change
  id = "Amazon_EventBridge_Invoke_Sqs_1541928649/arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1541928649"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.eventbridge_aws_health
  id = "Amazon_EventBridge_Invoke_Sqs_1568336830/arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_1568336830"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.eventbridge_docker_events
  id = "Amazon_EventBridge_Invoke_Sqs_2071571937/arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_2071571937"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.eventbridge_rds_events
  id = "Amazon_EventBridge_Invoke_Sqs_533425366/arn:aws:iam::686496667254:policy/service-role/Amazon_EventBridge_Invoke_Sqs_533425366"
}

# Monitoring IAM: Discord alert Lambda
import {
  to = module.prod_v1_iam.aws_iam_role.discord_alert
  id = "lookddak-discord-alert-role-pl51jpue"
}

import {
  to = module.prod_v1_iam.aws_iam_policy.discord_alert_logs
  id = "arn:aws:iam::686496667254:policy/service-role/AWSLambdaBasicExecutionRole-95b4d8dc-ae9a-4906-bfae-0a3702a265cf"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.discord_alert_logs
  id = "lookddak-discord-alert-role-pl51jpue/arn:aws:iam::686496667254:policy/service-role/AWSLambdaBasicExecutionRole-95b4d8dc-ae9a-4906-bfae-0a3702a265cf"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy_attachment.discord_alert_sqs
  id = "lookddak-discord-alert-role-pl51jpue/arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

import {
  to = module.prod_v1_iam.aws_iam_role_policy.discord_alert_status_logs_read
  id = "lookddak-discord-alert-role-pl51jpue:LamdaRole"
}
