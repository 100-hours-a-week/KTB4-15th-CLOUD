# PostgreSQL 마이그레이션 R1 3차 리허설 결과

## 1. 리허설 개요

| 항목 | 내용 |
| --- | --- |
| 실행 ID | `r1-20261016-03-final` |
| 테스트 데이터 ID | `r1-20261016-03-final-live-retry1` |
| 전환 방향 | EC2 PostgreSQL → RDS PostgreSQL → EC2 PostgreSQL |
| 읽기 관찰 부하 | k6 10 RPS |
| 쓰기 부하 | pgbench 약 3 TPS |
| 최종 결과 | 성공 |

이번 리허설은 EC2와 RDS의 애플리케이션 역할을 `lookddak_app`으로 통일한 뒤, 서비스 요청과 DB 쓰기가 계속 발생하는 상태에서 PgBouncer의 연결 대상을 EC2 PostgreSQL에서 RDS PostgreSQL로 전환하고 다시 EC2로 원복하는 과정을 검증했다.

핵심 목표는 전환 전부터 사용하던 pgbench 연결이 끊어지지 않는지, 전환 중 발생한 데이터가 양쪽 PostgreSQL에 빠짐없이 반영되는지 확인하는 것이었다.

## 2. 수행 결과

| 검증 항목 | 결과 | 내용 |
| --- | --- | --- |
| 사전 검사 | 성공 | 컨테이너, 복제 방향, 복제 슬롯, pgbench 실행 상태 확인 |
| 정방향 복제 동기화 | 성공 | RDS가 EC2의 목표 WAL 위치까지 첫 번째 확인에서 따라옴 |
| EC2 → RDS 전환 | 성공 | PgBouncer PAUSE부터 RESUME까지 2초 소요 |
| RDS 신규 연결 | 성공 | `lookddak` DB에 `lookddak_app` 역할로 연결 |
| 기존 pgbench 연결 유지 | 성공 | 전환 전 프로세스가 종료되지 않았고 새 오류 0건 |
| RDS 전환 후 쓰기 | 성공 | 테스트 이벤트가 823건에서 868건으로 증가 |
| 역방향 복제 | 성공 | RDS의 868건이 EC2에도 868건까지 반영됨 |
| EC2 원복 | 성공 | PgBouncer를 EC2로 되돌리고 정방향 복제를 다시 활성화 |
| 원복 후 연결 유지 | 성공 | 대기 중이던 요청이 처리된 뒤 약 3 TPS와 수 ms 지연으로 회복 |
| pgbench 결과 | 성공 | 전체 관찰 구간에서 `0 failed` |
| 시퀀스 동기화 | 성공 | `products_id_seq`가 EC2와 RDS 모두 `49980`, `is_called=true`로 일치 |
| 최종 WAL 동기화 | 성공 | pgbench 종료 후 RDS가 EC2의 마지막 WAL까지 첫 번째 확인에서 따라옴 |
| 데이터 정합성 | 성공 | 7개 복제 대상 테이블의 행 수·중복·이벤트·체크섬 비교 결과 일치 |
| 서비스 읽기 관찰 | 성공 | k6 약 14분 실행, 8,509건 완료, 중단 및 실패 요청 로그 없음 |

자동 전환 스크립트의 핵심 성공 결과는 다음과 같다.

```text
PGBENCH_CONTINUITY_OK pid_alive=true new_errors=0
LIVE_WRITES_OK before=823 rds_after=868 ec2_after=868
SWITCHOVER_TO_RDS_SUCCEEDED pause_seconds=2
```

## 3. 전환 결과

EC2 → RDS 전환 과정에서 PgBouncer는 새로운 DB 작업을 잠시 대기시키고, RDS가 EC2의 마지막 WAL까지 반영한 것을 확인한 뒤 복제 방향과 연결 대상을 변경했다.

전환에 걸린 PAUSE 시간은 2초였다. 기존 pgbench 프로세스는 종료되지 않았으며, EC2와 RDS에서 같은 `lookddak_app` 역할과 SCRAM 인증 정보를 사용해 RDS에 정상적으로 다시 연결됐다.

RDS 전환 직후 일부 요청의 지연 시간이 일시적으로 증가했지만 실패는 발생하지 않았다. 이후 약 3 TPS와 9ms 수준으로 안정화됐다.

이는 2차 리허설에서 발생했던 `lookddak_ai_app`과 `lookddak_app`의 역할 불일치 문제가 해결됐음을 의미한다.

## 4. EC2 원복 결과

RDS에서 발생한 마지막 WAL이 EC2에 반영된 것을 확인한 뒤 다음 순서로 원복했다.

1. PgBouncer PAUSE
2. RDS → EC2 역방향 복제 따라잡기
3. `products_id_seq`를 RDS 기준으로 EC2에 반영
4. 역방향 구독 비활성화 및 역방향 복제 슬롯 제거
5. EC2 → RDS 정방향 구독 재활성화
6. PgBouncer 연결 대상을 EC2 PostgreSQL로 변경
7. PgBouncer RESUME

원복 중 PgBouncer에 새 서버 연결이 준비될 때까지 일부 요청이 큐에서 대기했다. 이 구간에서 최대 약 24초의 지연이 관찰됐지만 요청 실패는 없었다. 밀린 요청은 일시적으로 약 10.5 TPS로 처리된 뒤 다시 약 3 TPS와 2~4ms 수준으로 회복됐다.

따라서 데이터 유실이나 연결 종료는 없었지만, 실제 운영 전환에서는 원복 명령도 자동화해 요청 대기 시간을 줄일 필요가 있다.

## 5. 데이터 정합성 결과

pgbench를 정상 종료한 뒤 EC2의 마지막 WAL이 RDS까지 반영된 것을 확인했다.

이후 EC2와 RDS에서 다음 항목을 비교했다.

- 마이그레이션 테스트 이벤트 행 수
- 고유 이벤트 수와 중복 여부
- 이벤트별 데이터 체크섬
- `products`, `usage_amount`, `migration_test_events`
- LangGraph 체크포인트 관련 4개 테이블

최종 비교 결과는 다음과 같다.

```text
FORWARD_CAUGHT_UP_FINAL attempt=1
CONSISTENCY_OK
```

`CONSISTENCY_OK`는 7개 복제 대상 테이블의 비교 결과에 차이가 없다는 뜻이다.

## 6. 서비스 요청 관찰 결과

k6는 약 14분 동안 10 RPS로 실행됐으며 8,509건의 요청을 완료했다. 실행 로그에서 중단된 iteration과 실패 요청은 확인되지 않았다.

다만 k6를 수동 종료하는 과정에서 최종 threshold 요약과 `k6-summary.json` 파일이 생성되지 않았다. 따라서 이번 결과에는 실행 로그를 근거로 기록하며, 다음 리허설에서는 종료 신호를 k6 프로세스에 직접 전달해 최종 요약 파일까지 보관해야 한다.

## 7. 진행 중 보완한 사항

### pgbench 디버그 옵션 제거

최초 pgbench 명령의 `-d lookddak_ai`가 데이터베이스 지정이 아니라 디버그 옵션으로 처리됐다. 해당 실행을 중지하고 데이터베이스 이름을 명령 마지막에 배치해 다시 시작했다.

```text
pgbench ... lookddak_ai
```

재실행부터는 약 3 TPS와 `0 failed`가 정상적으로 기록됐다.

### 이전 전환 프로세스 잠금 제거

이전 명령의 `timeout`과 `sudo` 프로세스가 전환 잠금 파일을 계속 열고 있어 첫 번째 전환 실행이 시작 전에 중단됐다. 남아 있던 프로세스를 종료하고 잠금 상태를 초기화한 뒤 사전 검사를 다시 통과했다.

이 오류가 발생했을 때는 실제 PAUSE나 복제 방향 변경이 시작되지 않았으므로 현재 부하를 유지한 상태로 리허설을 이어갔다.

### 시퀀스 Boolean 값 재동기화

원복 명령에서 PostgreSQL Boolean 출력인 `true`를 `t`로만 비교해 EC2의 `is_called`가 일시적으로 `false`로 설정됐다. 값을 즉시 다시 읽어 `true`와 `t`를 모두 처리하도록 수정했고, 최종적으로 양쪽 값을 다음과 같이 맞췄다.

```text
RDS=49980|t
EC2=49980|t
```

## 8. 최종 상태

리허설 종료 후 서비스 경로와 복제 상태는 기존 EC2 기준으로 정상 복구됐다.

- PgBouncer 연결 대상: EC2 PostgreSQL
- PgBouncer PAUSE: 해제
- 정방향 구독: 활성화
- 정방향 복제 슬롯: `active=true`, `wal_status=reserved`
- 역방향 구독: 비활성화
- 역방향 복제 슬롯: 제거
- pgbench: 정상 종료
- EC2와 RDS 데이터: 일치

## 9. 결론과 다음 조치

R1 3차 리허설에서는 EC2 → RDS 전환, 기존 DB 연결 유지, 실시간 쓰기, RDS → EC2 역방향 복제, EC2 원복과 최종 데이터 정합성 검증까지 모두 성공했다.

2차 리허설의 실패 원인이었던 PostgreSQL 역할 불일치는 `lookddak_app` 통일로 해결됐다. 전환 중 요청 실패와 데이터 유실은 확인되지 않았다.

다음 단계에서는 다음 두 항목을 보완한다.

1. RDS → EC2 원복 명령을 자동화해 현재 약 24초까지 발생한 요청 대기 시간을 줄인다.
2. k6 종료와 결과 저장 절차를 개선해 최종 threshold 요약과 `k6-summary.json`을 항상 보관한다.
