# V1 MySQL 마이그레이션 부하 리허설

API 부하를 주는 동안 `cutover.sh`로 전환·롤백을 하고, 사용자 요청의 대기·에러와 데이터 정합성을 측정한다.

| 파일 | 실행 위치 | 역할 |
|---|---|---|
| `loadtest/loadtest.js` | 부하 머신 | k6 시나리오. 계정 준비(setup) → 쓰기·읽기 API 혼합 부하 |
| `loadtest/analyze.py` | 부하 머신 | k6 CSV를 API별·초별(UTC)로 요약, 정합성 기대값(`expected.txt`) 출력 |
| `observe.sh` | dev EC2 | ProxySQL·두 DB 상태를 1초마다 기록, 이상 구간 요약(`report`) |
| `check-integrity.sh` | dev EC2 | 기대값을 두 DB의 실제 값과 비교 (유실·결과불명·불일치 판정) |
| `cutover.sh`, `verify-sync.sh` | dev EC2 | 전환·롤백, 테이블 일치 확인 |

## 부하 구성

| 비율 | API | DB 동작 |
|---|---|---|
| 40% | `PATCH /api/v1/chat-rooms/{id}` | 채팅방 제목 `UPDATE` (제목은 매번 고유값 `lt-<VU>-<순번>` → 정합성 검증) |
| 20% | `POST /api/v1/products/{id}/purchase-link-clicks` | `click_count + 1` (카운터 검증) |
| 10% | `POST /api/v1/auth/refresh` | refresh token 조회·폐기·발급 (`SELECT` + `UPDATE` + `INSERT`) |
| 15% | `GET /api/v1/members/me` | 읽기 |
| 15% | `GET /api/v1/chat-rooms` | 읽기 |

- AI를 부르는 API는 쓰지 않는다. 채팅방은 만들기만 하고 스트림(`/stream`)에 접속하지 않으므로 AI 호출 없음
- VU 1개 = 계정 1개 (`loadtest01@example.com` ~). refresh token rotation이 계정끼리 섞이지 않게 VU 수를 계정 수로 고정
- 테스트 계정 비밀번호는 저장소에 두지 않는다. 실행할 때 `-e PASSWORD="$LT_PASSWORD"`로 넘김 (회원가입 규칙: 8~20자, 대·소문자·숫자·특수문자 포함)
- `setup`이 계정이 없으면 가입하고, 계정마다 채팅방을 하나 만든다 (실행할 때마다 새 채팅방)
- HTTP 타임아웃 60초 (ProxySQL 전환 대기 한도 30초보다 길게)

| 환경 변수 | 기본값 | 뜻 |
|---|---|---|
| `PASSWORD` | (필수) | 테스트 계정 비밀번호 |
| `BASE_URL` | `https://dev.lookddak.com` | 대상 |
| `ACCOUNTS` | 10 | 계정 수 = VU 수 |
| `RATE` | 20 | 초당 요청 수 |
| `DURATION` | 10m | 부하 시간 |
| `PRODUCT_ID` | 1 | 클릭 카운터 상품 |

k6 지표

| 지표 | 뜻 |
|---|---|
| `clicks_ok` | 2xx를 받은 클릭 수 → DB `click_count` 증가량과 같아야 함 |
| `clicks_not_ok` | 실패·타임아웃 클릭 (반영 여부 불명) |
| `api_errors` | API별 실패 (2xx 아님) |
| `relogins` | 401로 다시 로그인한 횟수 (refresh rotation이 꼬이면 증가) |
| `dropped_iterations` | 모든 VU가 대기 중이라 보내지 못한 요청 (전환 대기 동안 증가 가능) |

## 관측과 정합성 검증

모든 시각은 UTC로 맞춰 한 타임라인에서 본다 (`cutover.sh` 로그, `observe.sh`, `analyze.py` 초별 표).

| 층 | 도구 | 무엇을 보나 |
|---|---|---|
| 사용자 | `analyze.py` | 요청별 응답 시간·실패, 초별 지연·실패 |
| 전환 | `cutover.sh` 로그 | 단계별 시각(ms), ②·③, 쓰기 대기 |
| ProxySQL | `observe.sh` | 쓰기 대상, 서버별 `ConnUsed`·`ConnFree`, 에러·연결 획득 실패 |
| 복제 | `observe.sh` | 두 DB 복제 방향·스레드·지연·적용 위치·에러 |
| Spring | `docker logs lookddak-spring` | SQL 예외, read-only 에러 |
| RDS | CloudWatch (1분) | CPU, 연결 수, 쓰기 지연 (큰 흐름만) |

| 정합성 문제 | 탐지 |
|---|---|
| 쓰기 유실 (성공 응답인데 DB에 없음) | 클릭 증가량 < `clicks_ok`, 채팅방 제목 ≠ 마지막 성공 제목 (`check-integrity.sh`) |
| 결과 불명 반영 (실패 응답인데 반영) | 클릭 증가량 > `clicks_ok`, 제목 = 나중에 실패로 받은 제목 (`check-integrity.sh`, 경고) |
| 트랜잭션 일부 유실 | `relogins` > 0 (refresh token 교체 꼬임) |
| 두 DB 불일치 | `verify-sync.sh`, `check-integrity.sh` 두 DB 비교, 복제 에러 (`observe.sh`) |
| 쓰기 경로가 둘 (split-brain) | 쓰기 대상이 아닌 DB의 앱 연결, 보조로 `Com_insert/update/delete` 증가 (`observe.sh report`) |
| 전환 경계 오류 | `SOURCE_POS_WAIT` ≥ 0, 역방향 복제 Yes/Yes (`cutover.sh`), 사후 `verify-sync.sh` |

## 1. 부하 머신 (같은 리전 EC2, 리허설 후 삭제)

- AMI: Amazon Linux 2023 (arm64), `t4g.small`
- 서브넷: 인터넷으로 나갈 수 있는 곳 (퍼블릭 IP 또는 NAT)
- 보안 그룹: 인바운드 없음
- IAM 역할: `AmazonSSMManagedInstanceCore` (Session Manager 접속)

```bash
cd /tmp
curl -fsSLO https://github.com/grafana/k6/releases/download/v0.54.0/k6-v0.54.0-linux-arm64.tar.gz
tar xzf k6-v0.54.0-linux-arm64.tar.gz
sudo install -m 755 k6-v0.54.0-linux-arm64/k6 /usr/local/bin/k6
k6 version
mkdir -p ~/loadtest/results && cd ~/loadtest
REF=<커밋 해시>
for f in loadtest.js analyze.py; do curl -fsSLO "https://raw.githubusercontent.com/100-hours-a-week/KTB4-15th-CLOUD/$REF/v1-mysql-migration/loadtest/$f"; done
```

dev EC2의 스크립트도 같은 커밋으로 맞춘다 (`/opt/lookddak/v1-mysql-migration`, 해시 확인 후 `install`).

## 2. 기준 측정 (전환 없이)

비밀번호는 화면에 보이지 않게 입력해 셸 변수로 둔다.

```bash
read -rs LT_PASSWORD
export LT_PASSWORD
export K6_NO_USAGE_REPORT=true
```

```bash
cd ~/loadtest
k6 run -e PASSWORD="$LT_PASSWORD" -e RATE=20 -e DURATION=3m --summary-export results/baseline-summary.json --out csv=results/baseline.csv.gz loadtest.js
python3 analyze.py results/baseline.csv.gz
```

- 에러 0, p99가 안정적인지 확인. 이 값이 전환 중 측정의 비교 기준
- 같은 시간 dev EC2에서 `observe.sh`를 돌려 기준 상태(쓰기 대상이 아닌 DB의 `Com_*` 증가 여부 등)도 확인
- 에러가 있으면 부하를 줄이고(`RATE`) 원인부터 확인

## 3. 부하 중 전환·롤백

dev EC2 (`/opt/lookddak/v1-mysql-migration`)

```bash
OLD=lookddak-dev-mysql.cd8ekqeiua7b.ap-northeast-2.rds.amazonaws.com
NEW=lookddak-dev-v2-mysql.cd8ekqeiua7b.ap-northeast-2.rds.amazonaws.com
./cutover.sh dev $NEW --check
./check-integrity.sh dev $OLD $NEW --start
```

`--start`가 출력한 쓰기 대상(구 DB)의 `click_count`를 시작값으로 적어 둔다.

| 시각 | 부하 머신 | dev EC2 (창 1) | dev EC2 (창 2) |
|---|---|---|---|
| T-1분 | | | `./observe.sh dev $OLD $NEW` (끝까지 실행) |
| T+0 | `k6 run -e PASSWORD="$LT_PASSWORD" -e RATE=20 -e DURATION=12m --summary-export results/run-summary.json --out csv=results/run.csv.gz loadtest.js` | | |
| T+3분 | | `./cutover.sh dev $NEW` (구 → 신) | |
| T+7분 | | `./cutover.sh dev $OLD --check` → `./cutover.sh dev $OLD` (신 → 구) | |
| T+12분 | k6 종료 | | 1분 뒤 Ctrl+C |

- 리허설 중 Spring 배포·`infra/**` 머지 금지
- 전환 후 바로 롤백까지 하므로 `proxysql.cnf`는 바꾸지 않음
- `cutover.sh` 종료 코드가 2면 출력의 "수동 조치"부터 진행 (역방향 복제 확인 필요)

## 4. 검증 (판정 순서)

부하 머신

```bash
python3 analyze.py results/run.csv.gz --expected-out results/expected.txt
python3 -c "import json;m=json.load(open('results/run-summary.json'))['metrics'];print({k:m[k].get('count') for k in ('clicks_ok','clicks_not_ok','api_errors','relogins','dropped_iterations') if k in m})"
```

`analyze.py` 마지막의 "정합성 기대값" 블록(약 10줄)을 dev EC2의 `expected.txt`로 저장한다.

dev EC2

```bash
./observe.sh report logs/observe-<시각>.csv
./verify-sync.sh dev $NEW
./check-integrity.sh dev $OLD $NEW expected.txt <click_count 시작값>
docker logs --since 20m lookddak-spring 2>&1 | grep -iE "SQLException|ERROR|read-only" | tail -20
```

| 순서 | 확인 | 통과 기준 |
|---|---|---|
| 1 | `observe.sh report` | 쓰기 대상이 아닌 DB에 앱 연결 없음, 복제 에러 없음, ProxySQL 에러·연결 획득 실패 증가 없음 |
| 2 | `cutover.sh` 로그 | 두 번 모두 종료 코드 0, 역방향 복제 정상 |
| 3 | `verify-sync.sh` | 모든 테이블 일치 |
| 4 | `check-integrity.sh` | 제목·클릭 모두 OK, 두 DB 일치 (결과불명은 경고: 실패 시각과 cutover 단계 확인) |
| 5 | k6 | `relogins` 0, `api_errors` 0 |
| 6 | `analyze.py` 초별 표 | 전환·롤백 시각(cutover 로그 [1]~[5]) 주변에만 지연, 실패 0 |
| 7 | Spring 로그 | SQL 예외·read-only 에러 없음 |

## 5. 정리

- 부하 머신 삭제
- 상품 1 `click_count`는 실제 추천 상품 데이터이므로 시작값으로 되돌림 (쓰기 대상 DB에서 `UPDATE product SET click_count = <시작값> WHERE id = 1;`)
- 테스트 계정·채팅방은 dev 데이터로 남겨 두고, 필요하면 정리
