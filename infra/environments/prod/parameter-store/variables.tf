variable "rds_admin_username" {
  description = "Master username of the production MySQL instance"
  type        = string
}

variable "rds_database" {
  description = "Name of the production MySQL database"
  type        = string
}

variable "rds_host" {
  description = "DNS address of the production MySQL instance"
  type        = string
}

variable "rds_port" {
  description = "Port of the production MySQL instance"
  type        = number
}
