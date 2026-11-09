# Prod V3 공용 Queue·S3와 워크로드 IRSA

## 공유 범위

- V3는 신규 Queue나 이미지 Bucket을 만들지 않는다.
- V2 ECS와 V3 EKS는 기존 `lookddak-prod-v2-*` 피팅 Queue 3개와
  `lookddak-prod-images-686496667254-ap-northeast-2` Bucket을 함께 사용한다.
- Queue URL과 Bucket 이름은 `/lookddak/prod/v3/` 아래의 V3 전용 Parameter로 노출한다.
- 기존 V2 IAM Role과 Parameter는 변경하지 않는다.

## 최소 권한 기준

- IRSA Trust Policy는 정확한 EKS OIDC, Namespace, ServiceAccount 하나만 허용한다.
- 각 워크로드는 자신이 마운트할 SSM Parameter만 읽을 수 있다.
- `fitting-worker`는 요청 Queue 전송과 결과 Queue 소비만 할 수 있다.
- `vton-orchestrator`는 요청 Queue 소비, AI Queue 처리, 결과 Queue 전송만 할 수 있다.
- S3 권한은 전신 이미지와 피팅 결과 Prefix별 읽기·쓰기로 제한한다.
- DLQ 직접 소비·삭제 권한과 Bucket 전체 삭제 권한은 애플리케이션 Role에 주지 않는다.

## V2/V3 공용 Queue 운영 기준

Queue 메시지는 먼저 가져간 Worker 한 곳에서만 처리된다. V2와 V3를 함께 운영하려면
동일한 메시지 계약, DB Schema, S3 Key 규칙, Webhook 형식을 지원하는 이미지끼리 배포한다.

공용 Queue의 backlog는 V2와 V3를 합친 값이므로 두 환경이 동시에 backlog만으로 독립
Auto Scaling하면 과도하게 확장될 수 있다. 공존 기간에는 기존 V2 CPU·Memory Scaling을
유지하고, Queue 기반 Scaling은 V3 KEDA 한 곳에서만 활성화한다. KEDA 적용 전에는 V3
Worker replica를 고정하며, 전환 후 V2 Worker를 중지한 다음 임계값을 다시 조정한다.

## 로그 구분

- V2 ECS: `environment=prod`, `version=v2`, ECS cluster/service/task로 구분한다.
- V3 EKS: `environment=prod`, `version=v3`, cluster/namespace/workload/pod로 구분한다.
- 공용 `fitting_job_id`와 SQS message ID를 양쪽 로그에 함께 남겨 처리 주체를 추적한다.
- 실제 로그 Label 주입은 후속 GitOps 모니터링 구성에서 적용한다.

## 보호 설정과 복구

- RDS는 Single-AZ를 유지하며 MySQL 7일, PostgreSQL 14일 PITR과 삭제 보호를 사용한다.
- Main Queue는 4일, DLQ는 14일 보존하며 SSE와 TLS 강제를 사용한다.
- 이미지 Bucket은 Versioning을 사용한다. 현재 객체는 자동 삭제하지 않고, 이전 Version은
  30일 보존한 뒤 정리한다. 중단된 Multipart Upload는 하루 뒤 제거한다.

### S3 객체 복구

1. `aws s3api list-object-versions`로 삭제 전 Version ID를 찾는다.
2. 해당 Version을 `aws s3api copy-object`로 같은 Key에 복사해 최신 Version으로 만든다.
3. 서비스에서 객체 조회를 확인하고 작업 ID와 복구 Version ID를 운영 기록에 남긴다.

### SQS DLQ 복구

1. 처리 실패 원인과 배포 이미지 호환성을 먼저 수정한다.
2. DLQ 메시지 본문과 대상 `fitting_job_id`의 DB 상태를 대조한다.
3. SQS StartMessageMoveTask로 연결된 원본 Queue에 Redrive한다.
4. 중복 처리 방지 Lease와 최종 DB·S3 결과를 확인한다.

### RDS 복구

PITR은 기존 DB를 덮어쓰지 않고 새 임시 DB 인스턴스로 복원한다. 필요한 행을 검증·추출한
후 운영 DB에 반영하고 임시 인스턴스를 제거한다. Multi-AZ 전환은 이 구성의 범위가 아니다.
