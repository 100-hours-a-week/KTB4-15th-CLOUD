# Single Dev Runtime AWS Resources

단일 EC2 Docker Compose 환경이 사용하는 AWS 런타임 자원입니다.

## 구성

- ECR: `lookddak-dev-nextjs`, `lookddak-dev-spring`, `lookddak-dev-fastapi`, `lookddak-dev-crawler`
- 기존 이미지 S3: `lookddak-prod-images-686496667254-ap-northeast-2` 재사용
- DB 백업 S3: `lookddak-dev-single-db-backup-686496667254-ap-northeast-2`
- SSM 경로: `/lookddak/dev/single/*`
- CloudWatch Logs: `/lookddak/dev/single`
- EC2 Instance Role 런타임 최소 권한

## 기존 Fitting Queue 보존

다음 기존 Dev V2 Main Queue와 대응 DLQ를 그대로 사용합니다.

- `lookddak-dev-v2-be-fitting-request`
- `lookddak-dev-v2-ai-fitting-response`
- `lookddak-dev-v2-be-fitting-response`

Queue와 DLQ는 `data.aws_sqs_queue`로 조회만 합니다. 이 모듈은 기존 Queue를 생성·수정·삭제하거나 Terraform state로 편입하지 않습니다.

## Secret 입력

SecureString은 Terraform state에 실제 값을 기록하지 않기 위해 `PENDING_MANUAL_CONFIGURATION` write-only 초기값으로 생성합니다. Docker Compose 배포 전에 `/lookddak/dev/single/*`의 placeholder를 실제 값으로 교체해야 합니다.
