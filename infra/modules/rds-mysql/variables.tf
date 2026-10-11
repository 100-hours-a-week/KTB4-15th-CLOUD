# ---------------------------------------------------------------
# 이름·환경
# ---------------------------------------------------------------
variable "name_prefix" {
  description = "리소스 이름 접두사 (예: lookddak-prod → lookddak-prod-mysql)"
  type        = string
}

variable "environment" {
  description = "Environment 태그 값 (prod, dev)"
  type        = string
}

# ---------------------------------------------------------------
# 네트워크
# ---------------------------------------------------------------
variable "subnet_ids" {
  description = "DB Subnet Group에 넣을 private subnet ID 목록 (2개 AZ 이상)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "RDS에 연결할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "availability_zone" {
  description = "Single-AZ일 때 배치할 AZ (Multi-AZ면 null)"
  type        = string
  default     = null
}

variable "multi_az" {
  description = "Multi-AZ 배포 여부"
  type        = bool
  default     = false
}

variable "subnet_group_description" {
  description = "DB Subnet Group 설명"
  type        = string
}

# ---------------------------------------------------------------
# 엔진·파라미터
# ---------------------------------------------------------------
variable "engine_version" {
  description = "MySQL 엔진 버전 (예: 8.4.11)"
  type        = string
}

variable "parameter_group_family" {
  description = "파라미터 그룹 family (예: mysql8.4)"
  type        = string
}

variable "parameter_group_description" {
  description = "파라미터 그룹 설명 (변경 시 파라미터 그룹이 교체되므로 주의)"
  type        = string
}

variable "parameters" {
  description = "파라미터 그룹에 설정할 MySQL 파라미터"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "option_group_name" {
  description = "옵션 그룹 이름"
  type        = string
  default     = "default:mysql-8-4"
}

# ---------------------------------------------------------------
# 인스턴스·스토리지
# ---------------------------------------------------------------
variable "instance_class" {
  description = "DB 인스턴스 클래스 (예: db.t4g.micro)"
  type        = string
}

variable "db_name" {
  description = "생성할 초기 데이터베이스 이름"
  type        = string
}

variable "allocated_storage" {
  description = "할당 스토리지 (GiB)"
  type        = number
}

variable "max_allocated_storage" {
  description = "스토리지 자동 확장 상한 (GiB)"
  type        = number
}

variable "iops" {
  description = "gp3 IOPS (400GiB 미만은 기본 성능이 고정되어 지정 불가 → null)"
  type        = number
  default     = null
}

variable "storage_throughput" {
  description = "gp3 처리량 (MiB/s, 400GiB 미만은 null)"
  type        = number
  default     = null
}

# ---------------------------------------------------------------
# 계정 (기존 인스턴스 import 시 null)
# ---------------------------------------------------------------
variable "master_username" {
  description = "마스터 사용자 이름 (새로 만들 때만 지정)"
  type        = string
  default     = null
}

variable "manage_master_user_password" {
  description = "마스터 비밀번호를 RDS가 Secrets Manager로 관리 (새로 만들 때만 지정, 값이 state에 남지 않음)"
  type        = bool
  default     = null
}

# ---------------------------------------------------------------
# 백업·유지보수·보호
# ---------------------------------------------------------------
variable "backup_retention_period" {
  description = "자동 백업 보존 기간 (일)"
  type        = number
}

variable "backup_window" {
  description = "백업 시간대 (UTC, 예: 18:00-18:30)"
  type        = string
}

variable "maintenance_window" {
  description = "유지보수 시간대 (UTC, 예: sun:19:00-sun:19:30)"
  type        = string
}

variable "deletion_protection" {
  description = "삭제 보호 (true면 AWS가 삭제 요청을 거부)"
  type        = bool
}

variable "skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 생략 여부"
  type        = bool
}

variable "delete_automated_backups" {
  description = "삭제 시 자동 백업도 함께 삭제할지 여부"
  type        = bool
  default     = true
}
