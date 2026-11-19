variable "instance_role_name" {
  description = "IAM role used by the Single Dev EC2 instance"
  type        = string
}

variable "images_bucket_name" {
  description = "Existing durable image bucket reused by Single Dev"
  type        = string
  default     = "lookddak-prod-images-686496667254-ap-northeast-2"
}
