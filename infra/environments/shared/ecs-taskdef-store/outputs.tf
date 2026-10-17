output "bucket_name" {
  description = "ECS Task Definition 템플릿 버킷 이름"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ECS Task Definition 템플릿 버킷 ARN"
  value       = aws_s3_bucket.this.arn
}
