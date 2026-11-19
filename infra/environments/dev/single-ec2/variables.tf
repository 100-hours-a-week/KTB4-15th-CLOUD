variable "vpc_cidr" {
  description = "CIDR block for the Single Dev VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the Single Dev public subnet"
  type        = string
  default     = "10.30.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone for the EC2 instance and data volume"
  type        = string
  default     = "ap-northeast-2a"
}

variable "instance_type" {
  description = "ARM64 instance type for the Docker Compose host"
  type        = string
  default     = "t4g.xlarge"

  validation {
    condition     = startswith(var.instance_type, "t4g.") || startswith(var.instance_type, "m7g.") || startswith(var.instance_type, "c7g.")
    error_message = "instance_type must be an ARM64 t4g, m7g, or c7g instance type."
  }
}

variable "root_volume_size_gib" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size_gib >= 20
    error_message = "root_volume_size_gib must be at least 20 GiB."
  }
}

variable "data_volume_size_gib" {
  description = "Persistent application and database EBS volume size in GiB"
  type        = number
  default     = 100

  validation {
    condition     = var.data_volume_size_gib >= 50
    error_message = "data_volume_size_gib must be at least 50 GiB."
  }
}
