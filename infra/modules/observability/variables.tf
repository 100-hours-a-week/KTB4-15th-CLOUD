variable "environment" {
  description = "Environment name used in resource names and tags (dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private App 2a subnet ID for the monitoring server"
  type        = string
}

variable "private_ip_host_number" {
  description = "Host number of the fixed private IP inside the subnet CIDR (e.g. 250 -> 10.30.21.250)"
  type        = number
  default     = 250
}

variable "instance_type" {
  description = "Monitoring server instance type"
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root volume size in GiB (OS, container images, Prometheus, Loki WAL/cache, Grafana)"
  type        = number
  default     = 30
}

variable "ecs_cluster_arn" {
  description = "V2 ECS cluster ARN for task stopped events"
  type        = string
}

variable "lambda_subnet_ids" {
  description = "Private App subnet IDs (2a, 2c) for lambda-promtail"
  type        = list(string)
}

variable "grafana_domain_name" {
  description = "Public domain for Grafana behind the V2 ALB"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 public hosted zone ID for lookddak.com"
  type        = string
}

variable "https_listener_arn" {
  description = "V2 ALB HTTPS listener ARN"
  type        = string
}

variable "alb_security_group_id" {
  description = "V2 ALB security group ID"
  type        = string
}

variable "alb_dns_name" {
  description = "V2 ALB DNS name"
  type        = string
}

variable "alb_zone_id" {
  description = "V2 ALB canonical hosted zone ID"
  type        = string
}

variable "ecs_task_security_group_ids" {
  description = "ECS task security group IDs that run the ecs_exporter sidecar (service => SG ID)"
  type        = map(string)
}

variable "mysql_security_group_id" {
  description = "V2 MySQL security group ID (mysqld_exporter 접속)"
  type        = string
}

variable "postgresql_security_group_id" {
  description = "V2 PostgreSQL security group ID (postgres_exporter 접속)"
  type        = string
}

variable "taskdef_bucket_name" {
  description = "ECS Task Definition 템플릿 버킷 (Fluent Bit 설정 파일도 함께 둔다)"
  type        = string
}

variable "taskdef_bucket_arn" {
  description = "ECS Task Definition 템플릿 버킷 ARN"
  type        = string
}

variable "firelens_task_role_names" {
  description = "FireLens를 쓰는 서비스별 Task Role 이름 (service => role name)"
  type        = map(string)
}

variable "app_log_group_names" {
  description = "서비스별 앱 로그 그룹 이름 (service => log group name)"
  type        = map(string)
}

variable "db_query_log_instance_ids" {
  description = "db-log-tailer가 로그 파일을 읽을 RDS 인스턴스 ID 목록"
  type        = list(string)
}

variable "extra_subscribed_log_group_names" {
  description = "ecs task stopped 외에 lambda-promtail로 구독할 CloudWatch 로그 그룹 이름"
  type        = list(string)
  default     = []
}

variable "grafana_listener_rule_priority" {
  description = "Grafana(Cognito 인증) HTTPS 리스너 규칙 우선순위"
  type        = number
  default     = 40
}

variable "grafana_logout_listener_rule_priority" {
  description = "Grafana 로그아웃 HTTPS 리스너 규칙 우선순위"
  type        = number
  default     = 39
}
