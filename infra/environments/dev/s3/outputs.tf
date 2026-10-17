output "images_bucket_name" {
  description = "dev 이미지 버킷 이름"
  value       = aws_s3_bucket.images.id
}
