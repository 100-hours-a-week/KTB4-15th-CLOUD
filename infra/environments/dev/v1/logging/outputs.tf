output "log_group_arns" {
  description = "dev 로그 그룹 ARN 목록 (dev EC2 로그 쓰기 권한에서 사용)"
  value       = [for g in aws_cloudwatch_log_group.this : g.arn]
}
