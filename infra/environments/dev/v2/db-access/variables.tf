variable "vpc_id" {
  description = "Dev VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private App 2a subnet ID for the SSM DB access node"
  type        = string
}

variable "mysql_security_group_id" {
  description = "Dev V2 MySQL RDS security group ID"
  type        = string
}

variable "postgresql_security_group_id" {
  description = "Dev V2 PostgreSQL RDS security group ID"
  type        = string
}

variable "mysql_endpoint" {
  description = "Dev V2 MySQL RDS endpoint"
  type        = string
}

variable "postgresql_endpoint" {
  description = "Dev V2 PostgreSQL RDS endpoint"
  type        = string
}

variable "tunnel_user_name" {
  description = "Existing IAM User that receives DB port-forwarding permissions"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the private SSM DB access node"
  type        = string
  default     = "t4g.micro"
}

