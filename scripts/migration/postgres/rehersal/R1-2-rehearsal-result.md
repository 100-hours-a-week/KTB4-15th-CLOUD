# PostgreSQL 마이그레이션 R1 2차 리허설 결과

## 1. 리허설 개요

| 항목 | 내용 |
| --- | --- |
| 실행 ID | `r1-20261015-02` |
| 테스트 데이터 ID | `r1-20261015-02-live` |
| 전환 방향 | EC2 PostgreSQL → RDS PostgreSQL |
| 읽기 관찰 부하 | k6 10 RPS |
| 쓰기 부하 | pgbench 약 3 TPS |
| 최종 결과 | 실패 — 기존 pgbench 연결 유지 실패 |

이번 리허설은 서비스 요청과 DB 쓰기가 계속 발생하는 상태에서 PgBouncer의 연결 대상을 EC2 PostgreSQL에서 RDS PostgreSQL로 전환하고, 기존 연결이 끊기지 않는지 확인하기 위해 수행했다.

## 2. 수행 결과

| 검증 항목 | 결과 | 내용 |
| --- | --- | --- |
| 사전 검사 | 성공 | 컨테이너 상태, 정방향 복제, pgbench 실행 상태 확인 |
| PgBouncer PAUSE | 성공 | 전환 작업 동안 2초간 PAUSE |
| 정방향 복제 동기화 | 성공 | RDS가 EC2의 목표 WAL 위치까지 반영, 첫 번째 확인에서 완료 |
| 시퀀스 동기화 | 성공 | `products_id_seq=49980`을 RDS에 반영 |
| 복제 방향 전환 | 성공 | 정방향 복제를 끄고 역방향 복제를 활성화 |
| RDS 신규 연결 | 성공 | `lookddak` DB의 `lookddak_app` 사용자로 연결 확인 |
| 기존 pgbench 연결 유지 | 실패 | 기존 연결 4개가 RDS 인증에 실패하며 종료 |
| 실패 후 EC2 복구 | 성공 | PgBouncer와 정방향 복제를 EC2 기준으로 복구 |
| 테스트 데이터 확인 | 성공 | EC2와 RDS 모두 1,913건으로 일치 |

## 3. 실패 원인

EC2와 RDS에서 사용하는 PostgreSQL 애플리케이션 역할이 서로 달랐다.

| 구분 | EC2 PostgreSQL | RDS PostgreSQL |
| --- | --- | --- |
| 애플리케이션 역할 | `lookddak_ai_app` | `lookddak_app` |
| PgBouncer 백엔드 사용자 지정 | 없음 | `user=lookddak_app` |

전환 후 새로 생성한 연결에는 RDS용 설정의 `user=lookddak_app`이 적용되어 정상적으로 연결됐다. 하지만 전환 전에 이미 열려 있던 pgbench 연결은 기존 `lookddak_ai_app` 사용자 정보를 유지했다. RDS에는 이 역할이 없으므로 다음 인증 오류가 발생했고 pgbench 프로세스가 종료됐다.

```text
FATAL: password authentication failed for user "lookddak_ai_app"
```

즉, EC2에서 RDS로 연결 대상은 정상적으로 바뀌었지만, 기존 세션의 백엔드 사용자가 양쪽 DB에서 동일하지 않아 연결 연속성 검증에 실패했다.

## 4. 사전 검사 오류와 수정

실제 전환 전에 `ssm-user`가 PgBouncer 설정 파일과 pgbench 로그를 읽지 못해 사전 검사가 두 차례 중단됐다. 파일은 존재했지만 스크립트가 일부 검사를 `sudo` 없이 실행한 것이 원인이었다.

해당 검사를 `sudo test`, `sudo grep`으로 수정했으며, 이후 `ssm-user` 권한으로 사전 검사가 정상 통과했다. 이 오류가 발생한 동안에는 실제 PAUSE나 DB 전환이 실행되지 않았다.

## 5. 복구 상태

실패 감지 후 자동 복구 로직이 실행되어 서비스 연결을 EC2 PostgreSQL로 되돌렸다.

- PgBouncer: EC2 PostgreSQL 연결, healthy
- 정방향 구독: 활성화
- 정방향 복제 슬롯: active
- 역방향 구독: 비활성화
- 역방향 복제 슬롯: 제거됨
- EC2 테스트 데이터: 1,913건
- RDS 테스트 데이터: 1,913건

## 6. 결론과 다음 조치

R1 2차 리허설에서는 WAL 동기화, 시퀀스 동기화, 복제 방향 전환, RDS 신규 연결과 2초 PAUSE까지 성공했다. 하지만 기존 pgbench 연결이 종료되었으므로 무중단 전환 합격 기준은 충족하지 못했다.

다음 리허설 전에는 EC2에도 같은 `lookddak_app` 역할과 비밀번호를 만들고 필요한 스키마·테이블·시퀀스 권한을 부여한다. FastAPI와 pgbench도 PgBouncer에 `lookddak_app`으로 접속하게 하여 클라이언트와 양쪽 PostgreSQL 백엔드 역할을 통일한 뒤, 새로운 실행 ID로 R1 3차 리허설을 수행한다.
