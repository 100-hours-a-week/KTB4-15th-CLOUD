variable "subnet_id" {
  description = "ID of the public subnet used by the V1 application instance"
  type        = string
}

variable "security_group_id" {
  description = "ID of the application security group attached to the V1 instance"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to the V1 instance"
  type        = string
}
