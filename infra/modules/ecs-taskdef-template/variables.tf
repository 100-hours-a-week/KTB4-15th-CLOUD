variable "bucket_name" {
  description = "템플릿을 저장할 S3 버킷 이름"
  type        = string
}

variable "s3_key" {
  description = "템플릿 객체 키 (예: dev/v2/spring.json)"
  type        = string
}

variable "family" {
  description = "Task Definition family"
  type        = string
}

variable "cpu" {
  description = "Task CPU 단위 (예: 1024)"
  type        = number
}

variable "memory" {
  description = "Task 메모리 MiB (예: 2048)"
  type        = number
}

variable "cpu_architecture" {
  description = "Fargate CPU 아키텍처 (ARM64 또는 X86_64)"
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "task_role_arn" {
  description = "Task Role ARN"
  type        = string
}

variable "execution_role_arn" {
  description = "Task Execution Role ARN"
  type        = string
}

variable "container_name" {
  description = "컨테이너 이름 (ECS Service의 load_balancer.container_name과 같아야 함)"
  type        = string
}

variable "image_repository_url" {
  description = "ECR 저장소 URL. image는 <URL>@__DIGEST__로 저장되고 CI가 __DIGEST__를 sha256:...로 바꾼다"
  type        = string
}

variable "environment" {
  description = "평문 환경 변수 (이름 => 값)"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "SSM Parameter Store 참조 환경 변수 (이름 => 파라미터 이름 또는 ARN)"
  type        = map(string)
  default     = {}
}

variable "port_mappings" {
  description = "컨테이너 포트 (Service Connect가 name을 참조)"
  type = list(object({
    name           = string
    container_port = number
    app_protocol   = optional(string, "http")
  }))
  default = []
}

variable "log_group_name" {
  description = "awslogs 로그 그룹 이름"
  type        = string
}

variable "log_region" {
  description = "awslogs 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "command" {
  description = "컨테이너 command (null이면 넣지 않고 이미지의 CMD를 쓴다). 예: 스케줄 작업의 실행 모드"
  type        = list(string)
  default     = null
}

variable "health_check" {
  description = "컨테이너 헬스 체크 (null이면 넣지 않음). 시간 단위는 초"
  type = object({
    command      = list(string)
    interval     = optional(number, 30)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 0)
  })
  default = null
}

variable "tags" {
  description = "Task Definition 태그 (revision 등록 시 함께 적용)"
  type        = map(string)
  default     = {}
}
