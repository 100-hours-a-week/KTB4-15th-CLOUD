# Dev 로컬 피팅 테스트 Queue

배포 중인 Dev V2·V3 Worker와 메시지를 경쟁하지 않고 로컬 BE·AI 프로세스끼리 전체 피팅 흐름을 검증하기 위한 Queue다.

## Queue

- `lookddak-dev-local-be-fitting-request`
- `lookddak-dev-local-ai-fitting-response`
- `lookddak-dev-local-be-fitting-response`

각 Main Queue에는 동일한 이름의 `-dlq`가 연결된다. Visibility Timeout·보존기간·Long Polling·SSE-SQS·TLS 강제·Redrive 정책은 Dev V3 Queue와 같다.

## AWS 인증

기존 공유 사용자 `lookddak-dev-v2-mq-local-test`의 Access Key를 안전한 경로로 전달받아 로컬 AWS Profile에 한 번만 등록한다. Access Key를 Git·문서·채팅에 기록하지 않는다.

```bash
aws configure --profile lookddak-local-test
aws sts get-caller-identity --profile lookddak-local-test
```

## 공통 환경변수

Terraform Apply 후 Queue URL을 AWS에서 조회해 환경변수로 설정한다.

```bash
export AWS_PROFILE=lookddak-local-test AWS_REGION=ap-northeast-2 AWS_SDK_LOAD_CONFIG=1
export BE_FITTING_REQUEST_QUEUE_URL="$(aws sqs get-queue-url --profile "$AWS_PROFILE" --region "$AWS_REGION" --queue-name lookddak-dev-local-be-fitting-request --query QueueUrl --output text)"
export AI_FITTING_RESPONSE_QUEUE_URL="$(aws sqs get-queue-url --profile "$AWS_PROFILE" --region "$AWS_REGION" --queue-name lookddak-dev-local-ai-fitting-response --query QueueUrl --output text)"
export BE_FITTING_RESPONSE_QUEUE_URL="$(aws sqs get-queue-url --profile "$AWS_PROFILE" --region "$AWS_REGION" --queue-name lookddak-dev-local-be-fitting-response --query QueueUrl --output text)"
```

BE 로컬 실행에는 `AWS_PROFILE`, `AWS_REGION`, `BE_FITTING_REQUEST_QUEUE_URL`, `BE_FITTING_RESPONSE_QUEUE_URL`이 필요하다. AI Worker까지 함께 실행할 때는 세 Queue URL을 모두 설정한다.

## 연결 확인

다른 개발자의 메시지를 지우지 않도록 `PurgeQueue` 권한은 제공하지 않는다. 아래 조회로 연결과 권한만 확인한다.

```bash
aws sqs get-queue-attributes --profile "$AWS_PROFILE" --region "$AWS_REGION" --queue-url "$BE_FITTING_REQUEST_QUEUE_URL" --attribute-names QueueArn ApproximateNumberOfMessages
```
