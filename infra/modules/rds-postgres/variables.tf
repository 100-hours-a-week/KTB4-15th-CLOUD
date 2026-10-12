variable "identifier" {
  description = "RDS PostgreSQL instance identifier"
  type        = string
}

variable "environment" {
  description = "Environment tag value"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs in at least two Availability Zones"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two private subnet IDs are required."
  }
}

variable "security_group_ids" {
  description = "Security group IDs attached to PostgreSQL"
  type        = list(string)
}

variable "subnet_group_description" {
  description = "DB subnet group description"
  type        = string
}

variable "multi_az" {
  description = "Whether RDS creates a synchronous standby in another Availability Zone"
  type        = bool
  default     = true
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
}

variable "parameter_group_family" {
  description = "PostgreSQL parameter group family"
  type        = string
}

variable "parameter_group_description" {
  description = "PostgreSQL parameter group description"
  type        = string
}

variable "parameters" {
  description = "PostgreSQL parameter group settings"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_name" {
  description = "Initial PostgreSQL database name"
  type        = string
}

variable "allocated_storage" {
  description = "Initial gp3 storage size in GiB"
  type        = number
}

variable "max_allocated_storage" {
  description = "Storage autoscaling upper limit in GiB"
  type        = number

  validation {
    condition     = var.max_allocated_storage >= var.allocated_storage
    error_message = "max_allocated_storage must be greater than or equal to allocated_storage."
  }
}

variable "master_username" {
  description = "PostgreSQL administrator username"
  type        = string
}

variable "master_password_wo" {
  description = "Write-only administrator password that is not persisted in plan or state"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "master_password_wo_version" {
  description = "Version used to reapply the write-only administrator password"
  type        = number
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
}

variable "backup_window" {
  description = "Daily backup window in UTC"
  type        = string
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC"
  type        = string
}

variable "deletion_protection" {
  description = "Whether RDS deletion protection is enabled"
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when deleting the instance"
  type        = bool
}

variable "final_snapshot_identifier" {
  description = "Final snapshot identifier used when skip_final_snapshot is false"
  type        = string
  default     = null
}

variable "enabled_cloudwatch_logs_exports" {
  description = "PostgreSQL logs exported to CloudWatch Logs"
  type        = list(string)
  default     = ["postgresql", "upgrade"]
}
